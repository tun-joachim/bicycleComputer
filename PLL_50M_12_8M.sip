set_global_assignment -entity "PLL_50M_12_8M" -library "lib_PLL_50M_12_8M" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "PLL_50M_12_8M" -library "lib_PLL_50M_12_8M" -name IP_TOOL_VERSION "16.1"
set_global_assignment -entity "PLL_50M_12_8M" -library "lib_PLL_50M_12_8M" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_PLL_50M_12_8M" -name SPD_FILE [file join $::quartus(sip_path) "PLL_50M_12_8M.spd"]

set_global_assignment -library "lib_PLL_50M_12_8M" -name MISC_FILE [file join $::quartus(sip_path) "PLL_50M_12_8M_sim/PLL_50M_12_8M.vo"]
