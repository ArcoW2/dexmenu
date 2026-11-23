namespace Dexmenu.Settings;

/// <summary>The layouts Dexmenu ships (plan 02 3.10), named "Default A", "Default B", ...: written into the layouts
/// folder once each (settings.json "shipped" remembers which), so a layout the user deleted or changed is left as it
/// is. A new user's every other kind of right-click uses "Default A".</summary>
static class ShippedLayouts
{
    public const string First = "Default A";

    // The rules match Windows' texts (an English Windows): a rule on the verb is not yet possible.
    static readonly (string Name, string Text)[] All =
    [
        (First, """
        {
          "format": 2,
          "menu": {
            "id": "menu",
            "card": "Menu",
            "show": "column",
            "content": [
              {
                "id": "line1",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "cut",
                    "card": "Cut",
                    "icon": "E8C6",
                    "rules": [
                      {
                        "name": {
                          "equals": "Cut"
                        }
                      }
                    ]
                  },
                  {
                    "id": "copy",
                    "card": "Copy",
                    "icon": "E8C8",
                    "rules": [
                      {
                        "name": {
                          "equals": "Copy"
                        }
                      }
                    ]
                  },
                  {
                    "id": "paste",
                    "card": "Paste",
                    "icon": "E77F",
                    "rules": [
                      {
                        "name": {
                          "equals": "Paste"
                        }
                      }
                    ]
                  },
                  {
                    "id": "rename",
                    "card": "Rename",
                    "icon": "E8AC",
                    "rules": [
                      {
                        "name": {
                          "equals": "Rename"
                        }
                      }
                    ]
                  },
                  {
                    "id": "delete",
                    "card": "Delete",
                    "icon": "E74D",
                    "rules": [
                      {
                        "name": {
                          "equals": "Delete"
                        }
                      }
                    ]
                  }
                ]
              },
              {
                "id": "properties",
                "card": "Properties",
                "icon": "E946",
                "rules": [
                  {
                    "name": {
                      "equals": "Properties"
                    }
                  }
                ]
              },
              {
                "id": "d1",
                "divider": ""
              },
              {
                "id": "line2",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "open",
                    "card": "Open",
                    "icon": "E8E5",
                    "rules": [
                      {
                        "name": {
                          "equals": "Open"
                        }
                      }
                    ]
                  },
                  {
                    "id": "openwith",
                    "card": "Open with",
                    "icon": "E7AC",
                    "rules": [
                      {
                        "name": {
                          "regex": "^Open with(\\.\\.\\.)?$"
                        }
                      }
                    ]
                  }
                ]
              },
              {
                "id": "d2",
                "divider": ""
              },
              {
                "id": "rest",
                "card": "Rest",
                "rules": [
                  "remaining"
                ]
              },
              {
                "id": "d3",
                "divider": ""
              },
              {
                "id": "line3",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "about",
                    "note": "Dexmenu - default menu"
                  },
                  {
                    "id": "edit",
                    "card": "Edit menu...",
                    "rules": [
                      {
                        "own": "editMenu"
                      }
                    ]
                  },
                  {
                    "id": "windows",
                    "card": "Windows' menu",
                    "rules": [
                      {
                        "own": "windowsMenu"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """),
        ("Default B", """
        {
          "format": 2,
          "menu": {
            "id": "menu",
            "card": "Menu",
            "show": "column",
            "content": [
              {
                "id": "search",
                "search": true
              },
              {
                "id": "line1",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "cut",
                    "card": "Cut",
                    "icon": "E8C6",
                    "rules": [
                      {
                        "name": {
                          "equals": "Cut"
                        }
                      }
                    ]
                  },
                  {
                    "id": "copy",
                    "card": "Copy",
                    "icon": "E8C8",
                    "rules": [
                      {
                        "name": {
                          "equals": "Copy"
                        }
                      }
                    ]
                  },
                  {
                    "id": "paste",
                    "card": "Paste",
                    "icon": "E77F",
                    "rules": [
                      {
                        "name": {
                          "equals": "Paste"
                        }
                      }
                    ]
                  },
                  {
                    "id": "rename",
                    "card": "Rename",
                    "icon": "E8AC",
                    "rules": [
                      {
                        "name": {
                          "equals": "Rename"
                        }
                      }
                    ]
                  },
                  {
                    "id": "delete",
                    "card": "Delete",
                    "icon": "E74D",
                    "rules": [
                      {
                        "name": {
                          "equals": "Delete"
                        }
                      }
                    ]
                  }
                ]
              },
              {
                "id": "d1",
                "divider": ""
              },
              {
                "id": "line2",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "open",
                    "card": "Open",
                    "icon": "E8E5",
                    "rules": [
                      {
                        "name": {
                          "equals": "Open"
                        }
                      }
                    ]
                  },
                  {
                    "id": "openwith",
                    "card": "Open with",
                    "icon": "E7AC",
                    "rules": [
                      {
                        "name": {
                          "regex": "^Open with(\\.\\.\\.)?$"
                        }
                      }
                    ]
                  },
                  {
                    "id": "properties",
                    "card": "Properties",
                    "icon": "E946",
                    "rules": [
                      {
                        "name": {
                          "equals": "Properties"
                        }
                      }
                    ]
                  }
                ]
              },
              {
                "id": "d2",
                "divider": ""
              },
              {
                "id": "line3",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "archive",
                    "card": "Archive",
                    "title": "Archive",
                    "rules": [
                      {
                        "name": {
                          "regex": "^(7-Zip|WinRAR|Extract All\\.\\.\\.)$"
                        }
                      }
                    ],
                    "show": "row"
                  },
                  {
                    "id": "code",
                    "card": "Code",
                    "title": "Code",
                    "rules": [
                      {
                        "name": {
                          "regex": "^Open (with|in) (Code|Visual Studio)"
                        }
                      }
                    ],
                    "show": "row"
                  }
                ]
              },
              {
                "id": "line4",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "git",
                    "card": "Git",
                    "title": "Git",
                    "rules": [
                      {
                        "name": {
                          "regex": "^(TortoiseGit$|Git |Open Git )"
                        }
                      }
                    ],
                    "show": "row"
                  },
                  {
                    "id": "svn",
                    "card": "SVN",
                    "title": "SVN",
                    "rules": [
                      {
                        "name": {
                          "regex": "^(TortoiseSVN$|SVN )"
                        }
                      }
                    ],
                    "show": "row"
                  }
                ]
              },
              {
                "id": "d3",
                "divider": ""
              },
              {
                "id": "rest",
                "card": "Rest",
                "rules": [
                  "remaining"
                ]
              },
              {
                "id": "d9",
                "divider": ""
              },
              {
                "id": "line5",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "about",
                    "note": "Dexmenu - cards per program"
                  },
                  {
                    "id": "edit",
                    "card": "Edit menu...",
                    "rules": [
                      {
                        "own": "editMenu"
                      }
                    ]
                  },
                  {
                    "id": "windows",
                    "card": "Windows' menu",
                    "rules": [
                      {
                        "own": "windowsMenu"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """),
        ("Default C", """
        {
          "format": 2,
          "menu": {
            "id": "menu",
            "card": "Menu",
            "show": "column",
            "content": [
              {
                "id": "line1",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "open",
                    "card": "Open",
                    "icon": "E8E5",
                    "content": [
                      {
                        "id": "openrules",
                        "card": "Open and edit",
                        "rules": [
                          {
                            "name": {
                              "regex": "^(Open|Edit|View|Print|Run)\\b"
                            }
                          }
                        ]
                      }
                    ],
                    "show": "submenu"
                  },
                  {
                    "id": "share",
                    "card": "Share and send",
                    "icon": "E72D",
                    "content": [
                      {
                        "id": "sharerules",
                        "card": "Share",
                        "rules": [
                          {
                            "name": {
                              "regex": "^(Share|Send to|Copy as path|Give access)"
                            }
                          }
                        ]
                      }
                    ],
                    "show": "submenu"
                  }
                ]
              },
              {
                "id": "line2",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "archive",
                    "card": "Archive",
                    "icon": "E7B8",
                    "content": [
                      {
                        "id": "archiverules",
                        "card": "Archive",
                        "rules": [
                          {
                            "name": {
                              "regex": "zip|7z|archive|extract|compress"
                            }
                          }
                        ]
                      }
                    ],
                    "show": "submenu"
                  },
                  {
                    "id": "vcs",
                    "card": "Version control",
                    "icon": "E8D4",
                    "content": [
                      {
                        "id": "vcsrules",
                        "card": "Version control",
                        "rules": [
                          {
                            "name": {
                              "regex": "git|svn|tortoise"
                            }
                          }
                        ]
                      }
                    ],
                    "show": "submenu"
                  }
                ]
              },
              {
                "id": "line3",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "file",
                    "card": "File",
                    "icon": "E7C3",
                    "content": [
                      {
                        "id": "filerules",
                        "card": "File",
                        "rules": [
                          {
                            "name": {
                              "any": [
                                "Cut",
                                "Copy",
                                "Paste",
                                "Rename",
                                "Delete",
                                "Properties"
                              ]
                            }
                          }
                        ]
                      }
                    ],
                    "show": "submenu"
                  },
                  {
                    "id": "more",
                    "card": "More",
                    "icon": "E712",
                    "content": [
                      {
                        "id": "rest",
                        "card": "Rest",
                        "rules": [
                          "remaining"
                        ]
                      }
                    ],
                    "show": "submenu"
                  }
                ]
              },
              {
                "id": "d9",
                "divider": ""
              },
              {
                "id": "line4",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "about",
                    "note": "Dexmenu - by task"
                  },
                  {
                    "id": "edit",
                    "card": "Edit menu...",
                    "rules": [
                      {
                        "own": "editMenu"
                      }
                    ]
                  },
                  {
                    "id": "windows",
                    "card": "Windows' menu",
                    "rules": [
                      {
                        "own": "windowsMenu"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """),
        ("Default D", """
        {
          "format": 2,
          "menu": {
            "id": "menu",
            "card": "Menu",
            "show": "column",
            "content": [
              {
                "id": "search",
                "search": true
              },
              {
                "id": "line1",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "most1",
                    "card": "Most used 1",
                    "rules": [
                      {
                        "used": "most",
                        "rank": 1,
                        "states": [
                          "enabled"
                        ],
                        "also": true,
                        "consume": false
                      }
                    ]
                  },
                  {
                    "id": "most2",
                    "card": "Most used 2",
                    "rules": [
                      {
                        "used": "most",
                        "rank": 2,
                        "states": [
                          "enabled"
                        ],
                        "also": true,
                        "consume": false
                      }
                    ]
                  },
                  {
                    "id": "most3",
                    "card": "Most used 3",
                    "rules": [
                      {
                        "used": "most",
                        "rank": 3,
                        "states": [
                          "enabled"
                        ],
                        "also": true,
                        "consume": false
                      }
                    ]
                  }
                ]
              },
              {
                "id": "d1",
                "divider": ""
              },
              {
                "id": "all",
                "card": "All items",
                "icon": "E700",
                "content": [
                  {
                    "id": "rest",
                    "card": "Rest",
                    "rules": [
                      "remaining"
                    ]
                  }
                ],
                "show": "submenu"
              },
              {
                "id": "d9",
                "divider": ""
              },
              {
                "id": "line2",
                "card": "Line",
                "show": "row",
                "shownWhen": "always",
                "content": [
                  {
                    "id": "about",
                    "note": "Dexmenu - minimal"
                  },
                  {
                    "id": "edit",
                    "card": "Edit menu...",
                    "rules": [
                      {
                        "own": "editMenu"
                      }
                    ]
                  },
                  {
                    "id": "windows",
                    "card": "Windows' menu",
                    "rules": [
                      {
                        "own": "windowsMenu"
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """),
    ];

    /// <summary>Every shipped layout not written before written now, when no layout of that name is there.</summary>
    public static void Ensure()
    {
        var settings = DataFolder.ReadSettings();
        var shipped = settings["shipped"] as System.Text.Json.Nodes.JsonArray ?? new System.Text.Json.Nodes.JsonArray();
        var done = shipped.Select(n => n?.GetValue<string>()).ToHashSet();
        var changed = false;
        foreach (var (name, text) in All)
        {
            if (done.Contains(name)) continue;
            var path = DataFolder.LayoutPath(name);
            if (!File.Exists(path))
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, text + Environment.NewLine);
            }
            shipped.Add(name);
            changed = true;
        }
        if (!changed) return;
        settings["shipped"] = shipped;
        DataFolder.WriteSettings(settings);
    }
}
