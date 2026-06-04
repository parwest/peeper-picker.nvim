-- Public UI surface used by the plugin orchestrator. The implementation is
-- split across focused submodules:
--   text / keymap / layout / highlight  - low-level primitives
--   header / list / preview_pane        - per-pane content rendering
--   view                                - rendering controller + view modes
--   lifecycle                           - window teardown + state reset
--   jump                                - opening the selected location
--   filter_panel                        - the filter sidebar
--   menu                                - window creation + keymaps
local menu = require("peeper_picker.ui.menu")
local view = require("peeper_picker.ui.view")
local lifecycle = require("peeper_picker.ui.lifecycle")

return {
  open_menu = menu.open,
  close_menu = lifecycle.close_menu,
  render_empty = view.render_empty,
  apply_filters = view.apply_filters,
}
