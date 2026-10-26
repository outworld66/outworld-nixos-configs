# FreeCAD MCP on Majesty

Majesty installs FreeCAD 1.1 and the FreeCAD MCP workbench. The matching MCP
server is registered for Pi and OpenCode and is launched on demand with `uvx`.

After switching the Majesty configuration, restart FreeCAD, select the **MCP
Addon** workbench, and click **Start RPC Server** in the FreeCAD MCP toolbar.
Then restart the Pi or OpenCode session. The addon listens on `127.0.0.1:9875`
by default; keep remote connections disabled. The MCP server requires the
FreeCAD GUI and its RPC server to be running.

The addon and server are pinned to matching upstream version 0.1.28. The MCP
tools can execute Python inside FreeCAD with the logged-in user's permissions;
only trusted local MCP clients should be enabled.
