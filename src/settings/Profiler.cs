using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;

namespace Dexmenu.Settings;

/// <summary>A sampling profile of one thread, and of the process's other threads while it waits
/// (docs/plans/16-PLAN-diagnostics.md 3.7): while it runs, a second thread
/// pauses it about every millisecond (a high-resolution timer), walks its call stack (x64 unwind data) and notes which DLLs are on it; the time
/// between samples is counted for each DLL on the stack ("on the stack") and for the function the thread was in
/// ("running in": the DLL and the nearest exported function before the address; for Windows' system calls, which
/// wait they were in). Nothing that can take a lock the paused thread may hold is done while it is paused: no allocation
/// on the native heap, no loader call (the unwind data is read from the DLL's own headers in memory, the DLL's name
/// once the thread runs again). Code that is not in a DLL (.NET's own) ends the walk: the frames above it, the ones
/// that matter, are walked by then.</summary>
sealed class Profiler
{
    const int MaxDepth = 256;
    const int PathLength = 8;   // DLLs in a call path, the function's own included
    const int ContextSize = 0x4D0, ContextFlagsOffset = 0x30, RspOffset = 0x98, RipOffset = 0xF8;
    const uint ContextFull = 0x10000B;   // CONTEXT_AMD64 | CONTROL | INTEGER | FLOATING_POINT

    readonly IntPtr thread;
    readonly ulong stackLow, stackHigh;
    readonly Thread sampler;
    volatile bool stop;
    readonly Dictionary<ulong, double> onStack = [];
    readonly Dictionary<string, double> runningIn = [];   // by "dll!function": the function the thread was in
    readonly Dictionary<string, double> paths = [];       // by the function and the DLLs that called it, innermost first
    readonly Dictionary<string, double> otherPaths = [];  // the other threads' paths while the profiled one waited
    readonly Dictionary<uint, (IntPtr Handle, ulong Low, ulong High)> others = [];
    readonly Dictionary<ulong, (uint Rva, string Name)[]> exports = [];
    ulong topPc;
    readonly Dictionary<ulong, (uint Rva, uint Count)> unwindTables = [];
    readonly Dictionary<ulong, string> names = [];   // read once the thread runs again: a DLL may be let go of later
    readonly ulong[] frames = new ulong[MaxDepth];
    readonly char[] nameBuffer = new char[1024];
    readonly HashSet<ulong> seen = [];
    double total;
    int samples;

    Profiler()
    {
        thread = OpenThread(0x0002 | 0x0008 | 0x0040 /* SUSPEND_RESUME | GET_CONTEXT | QUERY_INFORMATION */, false, GetCurrentThreadId());
        GetCurrentThreadStackLimits(out var low, out var high);
        stackLow = (ulong)low;
        stackHigh = (ulong)high;
        sampler = new Thread(Sample) { IsBackground = true, Priority = ThreadPriority.Highest };
    }

    /// <summary>Profiles the calling thread until Stop.</summary>
    public static Profiler Start()
    {
        var p = new Profiler();
        p.sampler.Start();
        return p;
    }

    /// <summary>Ends the profile; per DLL its path and ms on the stack and running in, the most on the stack first.
    /// Called before the profiled code's DLLs are let go, so their names can still be read.</summary>
    public JsonObject Stop()
    {
        stop = true;
        sampler.Join();
        CloseHandle(thread);
        var modules = new JsonArray();
        foreach (var (b, ms) in onStack.OrderByDescending(e => e.Value))
        {
            modules.Add(new JsonObject
            {
                ["module"] = names.GetValueOrDefault(b) ?? $"(unknown: 0x{b:X})",
                ["onStack"] = Math.Round(ms),
            });
        }
        var functions = new JsonArray();
        foreach (var (where, ms) in runningIn.OrderByDescending(e => e.Value))
            functions.Add(new JsonObject { ["function"] = where, ["ms"] = Math.Round(ms) });
        var calls = new JsonArray();
        foreach (var (path, ms) in paths.OrderByDescending(e => e.Value))
            calls.Add(new JsonObject { ["path"] = path, ["ms"] = Math.Round(ms) });
        var meanwhile = new JsonArray();
        foreach (var (path, ms) in otherPaths.OrderByDescending(e => e.Value))
            meanwhile.Add(new JsonObject { ["path"] = path, ["ms"] = Math.Round(ms) });
        return new JsonObject { ["total"] = Math.Round(total), ["samples"] = samples, ["modules"] = modules,
            ["runningIn"] = functions, ["paths"] = calls, ["otherThreads"] = meanwhile };
    }

    void Sample()
    {
        var context = Marshal.AllocHGlobal(ContextSize + 16);
        var aligned = (IntPtr)(((long)context + 15) & ~15L);   // CONTEXT must be 16-byte aligned
        // a high-resolution timer: Windows 11 ignores timeBeginPeriod for a process without a visible window
        var timer = CreateWaitableTimerExW(IntPtr.Zero, null, 0x2 /* HIGH_RESOLUTION */, 0x1F0003 /* TIMER_ALL_ACCESS */);
        var due = -10_000L;   // 1 ms, relative, in 100 ns
        var clock = Stopwatch.StartNew();
        var last = 0.0;
        var tick = 0;
        try
        {
            while (!stop)
            {
                if (timer != IntPtr.Zero && SetWaitableTimer(timer, ref due, 0, IntPtr.Zero, IntPtr.Zero, false))
                    WaitForSingleObject(timer, 100);
                else
                    Thread.Sleep(1);
                var now = clock.Elapsed.TotalMilliseconds;
                var weight = now - last;
                last = now;
                var depth = SampleThread(thread, stackLow, stackHigh, aligned);
                if (depth < 0) break;
                if (depth == 0) continue;
                samples++;
                total += weight;
                var where = Name(depth);
                runningIn[where] = runningIn.GetValueOrDefault(where) + weight;
                var key = PathOf(where, depth);
                paths[key] = paths.GetValueOrDefault(key) + weight;
                seen.Clear();
                for (var i = 0; i < depth; i++)
                    if (seen.Add(frames[i])) onStack[frames[i]] = onStack.GetValueOrDefault(frames[i]) + weight;
                // the thread waits: what the process's other threads do meanwhile (what it may wait for)
                if (!where.Contains("Wait", StringComparison.Ordinal)) continue;
                if (tick++ % 50 == 0) RefreshThreads();
                foreach (var (id, other) in others)
                {
                    var d = SampleThread(other.Handle, other.Low, other.High, aligned);
                    if (d <= 0) continue;
                    var w = Name(d);
                    if (w.Contains("WaitForWorkViaWorkerFactory", StringComparison.Ordinal)) continue;   // an idle pool thread
                    var runtime = false;
                    for (var i = 0; i < d; i++)
                        if (names[frames[i]].Contains(@"\dotnet\", StringComparison.OrdinalIgnoreCase)) runtime = true;
                    if (runtime) continue;   // .NET's own threads
                    var k = PathOf(w, d);
                    otherPaths[k] = otherPaths.GetValueOrDefault(k) + weight;
                }
            }
        }
        finally
        {
            if (timer != IntPtr.Zero) CloseHandle(timer);
            Marshal.FreeHGlobal(context);
            foreach (var (_, o) in others) CloseHandle(o.Handle);
        }
    }

    // One thread paused, its stack walked into frames, let go; the depth, -1 when it cannot be paused.
    int SampleThread(IntPtr handle, ulong low, ulong high, IntPtr context)
    {
        if (SuspendThread(handle) == uint.MaxValue) return -1;
        var depth = 0;
        try
        {
            Marshal.WriteInt32(context, ContextFlagsOffset, unchecked((int)ContextFull));
            if (GetThreadContext(handle, context)) depth = Walk(context, low, high);
        }
        finally { ResumeThread(handle); }
        for (var i = 0; i < depth; i++)
            if (!names.ContainsKey(frames[i]))
            {
                var n = GetModuleFileNameW((IntPtr)(long)frames[i], nameBuffer, nameBuffer.Length);
                names[frames[i]] = n > 0 ? new string(nameBuffer, 0, (int)n) : $"(unknown: 0x{frames[i]:X})";
            }
        return depth;
    }

    // The function the walked thread was in: "dll!function".
    string Name(int depth) => Path.GetFileName(names[frames[0]]) + "!" + ExportBefore(frames[0], topPc);

    // The path: the function, then each DLL that called it (one name for a run of frames in one DLL), up to PathLength.
    string PathOf(string where, int depth)
    {
        var path = new System.Text.StringBuilder(where);
        var shown = 1;
        for (var i = 1; i < depth && shown < PathLength; i++)
            if (frames[i] != frames[i - 1])
            {
                path.Append(" < ").Append(Path.GetFileName(names[frames[i]]));
                shown++;
            }
        return path.ToString();
    }

    // The process's other threads (not the profiled one, not the sampler), with their stacks' bounds (from their TEB).
    void RefreshThreads()
    {
        var pid = (uint)Environment.ProcessId;
        var me = GetCurrentThreadId();
        var main = GetThreadId(thread);
        var now = new HashSet<uint>();
        var snapshot = CreateToolhelp32Snapshot(0x4 /* TH32CS_SNAPTHREAD */, 0);
        if (snapshot == (IntPtr)(-1)) return;
        try
        {
            var entry = new ThreadEntry { Size = (uint)Marshal.SizeOf<ThreadEntry>() };
            for (var ok = Thread32First(snapshot, ref entry); ok; ok = Thread32Next(snapshot, ref entry))
                if (entry.OwnerProcessId == pid && entry.ThreadId != me && entry.ThreadId != main) now.Add(entry.ThreadId);
        }
        finally { CloseHandle(snapshot); }
        foreach (var gone in others.Keys.Where(k => !now.Contains(k)).ToList())
        {
            CloseHandle(others[gone].Handle);
            others.Remove(gone);
        }
        foreach (var id in now.Where(id => !others.ContainsKey(id)))
        {
            var h = OpenThread(0x0002 | 0x0008 | 0x0040, false, id);
            if (h == IntPtr.Zero) continue;
            var info = new ThreadBasicInformation();
            if (NtQueryInformationThread(h, 0, ref info, Marshal.SizeOf<ThreadBasicInformation>(), out _) != 0 || info.TebBaseAddress == IntPtr.Zero)
            {
                CloseHandle(h);
                continue;
            }
            var high = (ulong)Marshal.ReadInt64(info.TebBaseAddress, 0x08);   // NT_TIB.StackBase
            var low = (ulong)Marshal.ReadInt64(info.TebBaseAddress, 0x10);    // NT_TIB.StackLimit
            others[id] = (h, low, high);
        }
    }

    // The DLLs of the paused thread's frames, the innermost first, into frames; how many.
    int Walk(IntPtr context, ulong low, ulong high)
    {
        var depth = 0;
        while (depth < MaxDepth)
        {
            var pc = (ulong)Marshal.ReadInt64(context, RipOffset);
            var sp = (ulong)Marshal.ReadInt64(context, RspOffset);
            if (pc == 0 || sp < low || sp >= high) break;
            var b = ImageBase(pc);
            if (b == 0) break;   // not in a DLL (.NET's own code): the walk ends
            if (depth == 0) topPc = pc;
            frames[depth++] = b;
            var entry = FunctionEntry(b, pc);
            if (entry == IntPtr.Zero)
            {
                // a leaf function: its return address is at the top of the stack
                Marshal.WriteInt64(context, RipOffset, Marshal.ReadInt64((IntPtr)(long)sp));
                Marshal.WriteInt64(context, RspOffset, (long)(sp + 8));
            }
            else
                RtlVirtualUnwind(0, b, pc, entry, context, out _, out _, IntPtr.Zero);
        }
        return depth;
    }

    // The exported function the address is in, as near as the DLL's exports tell (the nearest one before it); read
    // with the thread running. Windows' own DLLs export their system calls by name (NtWaitForSingleObject, ...).
    string ExportBefore(ulong b, ulong pc)
    {
        if (!exports.TryGetValue(b, out var list))
        {
            var found = new List<(uint, string)>();
            var pe = b + (uint)Marshal.ReadInt32((IntPtr)(long)(b + 0x3C));
            var optional = pe + 0x18;
            if (Marshal.ReadInt16((IntPtr)(long)optional) == 0x20B)
            {
                var dir = (uint)Marshal.ReadInt32((IntPtr)(long)(optional + 0x70));
                if (dir != 0)
                {
                    var e = b + dir;
                    var count = (uint)Marshal.ReadInt32((IntPtr)(long)(e + 0x18));
                    var functionsRva = (uint)Marshal.ReadInt32((IntPtr)(long)(e + 0x1C));
                    var namesRva = (uint)Marshal.ReadInt32((IntPtr)(long)(e + 0x20));
                    var ordinalsRva = (uint)Marshal.ReadInt32((IntPtr)(long)(e + 0x24));
                    for (uint i = 0; i < count; i++)
                    {
                        var name = Marshal.PtrToStringAnsi((IntPtr)(long)(b + (uint)Marshal.ReadInt32((IntPtr)(long)(b + namesRva + i * 4)))) ?? "";
                        var ordinal = (ushort)Marshal.ReadInt16((IntPtr)(long)(b + ordinalsRva + i * 2));
                        found.Add(((uint)Marshal.ReadInt32((IntPtr)(long)(b + functionsRva + ordinal * 4u)), name));
                    }
                }
            }
            list = found.OrderBy(f => f.Item1).ToArray();
            exports[b] = list;
        }
        var rva = (uint)(pc - b);
        string best = "";
        foreach (var (r, n) in list)
        {
            if (r > rva) break;
            best = n;
        }
        return best.Length > 0 ? best : $"+0x{rva:X}";
    }

    // The DLL the address is in: its base (VirtualQuery: a system call, no lock); 0 when it is in none.
    static ulong ImageBase(ulong address)
    {
        if (VirtualQuery((IntPtr)(long)address, out var info, (IntPtr)Marshal.SizeOf<MemoryInfo>()) == IntPtr.Zero) return 0;
        return info.Type == 0x1000000 /* MEM_IMAGE */ ? (ulong)info.AllocationBase : 0;
    }

    // The function's unwind entry (RUNTIME_FUNCTION) from the DLL's exception directory, found by its address.
    IntPtr FunctionEntry(ulong b, ulong pc)
    {
        if (!unwindTables.TryGetValue(b, out var table))
        {
            var pe = b + (uint)Marshal.ReadInt32((IntPtr)(long)(b + 0x3C));
            var optional = pe + 0x18;
            table = Marshal.ReadInt16((IntPtr)(long)optional) == 0x20B   // PE32+
                ? ((uint)Marshal.ReadInt32((IntPtr)(long)(optional + 0x70 + 3 * 8)),
                   (uint)Marshal.ReadInt32((IntPtr)(long)(optional + 0x70 + 3 * 8 + 4)) / 12)
                : (0, 0);
            unwindTables[b] = table;
        }
        if (table.Count == 0) return IntPtr.Zero;
        var rva = (uint)(pc - b);
        int lo = 0, hi = (int)table.Count - 1;
        while (lo <= hi)
        {
            var mid = (lo + hi) / 2;
            var e = b + table.Rva + (ulong)mid * 12;
            var begin = (uint)Marshal.ReadInt32((IntPtr)(long)e);
            var end = (uint)Marshal.ReadInt32((IntPtr)(long)(e + 4));
            if (rva < begin) hi = mid - 1;
            else if (rva >= end) lo = mid + 1;
            else return (IntPtr)(long)e;
        }
        return IntPtr.Zero;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ThreadEntry
    {
        public uint Size, Usage, ThreadId, OwnerProcessId;
        public int BasePriority, DeltaPriority;
        public uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ThreadBasicInformation
    {
        public int ExitStatus;
        public IntPtr TebBaseAddress, UniqueProcess, UniqueThread, AffinityMask;
        public int Priority, BasePriority;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct MemoryInfo
    {
        public IntPtr BaseAddress, AllocationBase;
        public uint AllocationProtect;
        public ushort PartitionId;
        public IntPtr RegionSize;
        public uint State, Protect, Type;
    }

    [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll")] static extern uint GetThreadId(IntPtr thread);
    [DllImport("kernel32.dll")] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
    [DllImport("kernel32.dll")] static extern bool Thread32First(IntPtr snapshot, ref ThreadEntry entry);
    [DllImport("kernel32.dll")] static extern bool Thread32Next(IntPtr snapshot, ref ThreadEntry entry);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationThread(IntPtr thread, int infoClass, ref ThreadBasicInformation info, int length, out int returned);
    [DllImport("kernel32.dll")] static extern void GetCurrentThreadStackLimits(out IntPtr low, out IntPtr high);
    [DllImport("kernel32.dll")] static extern uint SuspendThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] static extern bool GetThreadContext(IntPtr thread, IntPtr context);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr VirtualQuery(IntPtr address, out MemoryInfo info, IntPtr length);
    [DllImport("kernel32.dll")] static extern IntPtr RtlVirtualUnwind(uint handlerType, ulong imageBase, ulong controlPc,
        IntPtr functionEntry, IntPtr context, out IntPtr handlerData, out ulong establisherFrame, IntPtr contextPointers);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetModuleFileNameW(IntPtr module, char[] name, int size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWaitableTimerExW(IntPtr attributes, string? name, uint flags, uint access);
    [DllImport("kernel32.dll")] static extern bool SetWaitableTimer(IntPtr timer, ref long due, int period, IntPtr completion, IntPtr arg, bool resume);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint ms);
}
