# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "BAUD_DIV" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BAUD_DIV_BT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BT_RST_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "DATA_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "HEX_FILE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LCD_RST_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LCD_WR_CYCLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SEG_GROUP_SWAP" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SEG_REVERSE_K" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SEG_SCAN_DIV" -parent ${Page_0}
  ipgui::add_param $IPINST -name "TIMER_DELAY" -parent ${Page_0}


}

proc update_PARAM_VALUE.BAUD_DIV { PARAM_VALUE.BAUD_DIV } {
	# Procedure called to update BAUD_DIV when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BAUD_DIV { PARAM_VALUE.BAUD_DIV } {
	# Procedure called to validate BAUD_DIV
	return true
}

proc update_PARAM_VALUE.BAUD_DIV_BT { PARAM_VALUE.BAUD_DIV_BT } {
	# Procedure called to update BAUD_DIV_BT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BAUD_DIV_BT { PARAM_VALUE.BAUD_DIV_BT } {
	# Procedure called to validate BAUD_DIV_BT
	return true
}

proc update_PARAM_VALUE.BT_RST_CYCLES { PARAM_VALUE.BT_RST_CYCLES } {
	# Procedure called to update BT_RST_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BT_RST_CYCLES { PARAM_VALUE.BT_RST_CYCLES } {
	# Procedure called to validate BT_RST_CYCLES
	return true
}

proc update_PARAM_VALUE.DATA_FILE { PARAM_VALUE.DATA_FILE } {
	# Procedure called to update DATA_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.DATA_FILE { PARAM_VALUE.DATA_FILE } {
	# Procedure called to validate DATA_FILE
	return true
}

proc update_PARAM_VALUE.HEX_FILE { PARAM_VALUE.HEX_FILE } {
	# Procedure called to update HEX_FILE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.HEX_FILE { PARAM_VALUE.HEX_FILE } {
	# Procedure called to validate HEX_FILE
	return true
}

proc update_PARAM_VALUE.LCD_RST_CYCLES { PARAM_VALUE.LCD_RST_CYCLES } {
	# Procedure called to update LCD_RST_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LCD_RST_CYCLES { PARAM_VALUE.LCD_RST_CYCLES } {
	# Procedure called to validate LCD_RST_CYCLES
	return true
}

proc update_PARAM_VALUE.LCD_WR_CYCLES { PARAM_VALUE.LCD_WR_CYCLES } {
	# Procedure called to update LCD_WR_CYCLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LCD_WR_CYCLES { PARAM_VALUE.LCD_WR_CYCLES } {
	# Procedure called to validate LCD_WR_CYCLES
	return true
}

proc update_PARAM_VALUE.SEG_GROUP_SWAP { PARAM_VALUE.SEG_GROUP_SWAP } {
	# Procedure called to update SEG_GROUP_SWAP when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SEG_GROUP_SWAP { PARAM_VALUE.SEG_GROUP_SWAP } {
	# Procedure called to validate SEG_GROUP_SWAP
	return true
}

proc update_PARAM_VALUE.SEG_REVERSE_K { PARAM_VALUE.SEG_REVERSE_K } {
	# Procedure called to update SEG_REVERSE_K when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SEG_REVERSE_K { PARAM_VALUE.SEG_REVERSE_K } {
	# Procedure called to validate SEG_REVERSE_K
	return true
}

proc update_PARAM_VALUE.SEG_SCAN_DIV { PARAM_VALUE.SEG_SCAN_DIV } {
	# Procedure called to update SEG_SCAN_DIV when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SEG_SCAN_DIV { PARAM_VALUE.SEG_SCAN_DIV } {
	# Procedure called to validate SEG_SCAN_DIV
	return true
}

proc update_PARAM_VALUE.TIMER_DELAY { PARAM_VALUE.TIMER_DELAY } {
	# Procedure called to update TIMER_DELAY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.TIMER_DELAY { PARAM_VALUE.TIMER_DELAY } {
	# Procedure called to validate TIMER_DELAY
	return true
}


proc update_MODELPARAM_VALUE.HEX_FILE { MODELPARAM_VALUE.HEX_FILE PARAM_VALUE.HEX_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.HEX_FILE}] ${MODELPARAM_VALUE.HEX_FILE}
}

proc update_MODELPARAM_VALUE.DATA_FILE { MODELPARAM_VALUE.DATA_FILE PARAM_VALUE.DATA_FILE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.DATA_FILE}] ${MODELPARAM_VALUE.DATA_FILE}
}

proc update_MODELPARAM_VALUE.BAUD_DIV { MODELPARAM_VALUE.BAUD_DIV PARAM_VALUE.BAUD_DIV } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BAUD_DIV}] ${MODELPARAM_VALUE.BAUD_DIV}
}

proc update_MODELPARAM_VALUE.BAUD_DIV_BT { MODELPARAM_VALUE.BAUD_DIV_BT PARAM_VALUE.BAUD_DIV_BT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BAUD_DIV_BT}] ${MODELPARAM_VALUE.BAUD_DIV_BT}
}

proc update_MODELPARAM_VALUE.LCD_WR_CYCLES { MODELPARAM_VALUE.LCD_WR_CYCLES PARAM_VALUE.LCD_WR_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LCD_WR_CYCLES}] ${MODELPARAM_VALUE.LCD_WR_CYCLES}
}

proc update_MODELPARAM_VALUE.LCD_RST_CYCLES { MODELPARAM_VALUE.LCD_RST_CYCLES PARAM_VALUE.LCD_RST_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LCD_RST_CYCLES}] ${MODELPARAM_VALUE.LCD_RST_CYCLES}
}

proc update_MODELPARAM_VALUE.SEG_SCAN_DIV { MODELPARAM_VALUE.SEG_SCAN_DIV PARAM_VALUE.SEG_SCAN_DIV } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SEG_SCAN_DIV}] ${MODELPARAM_VALUE.SEG_SCAN_DIV}
}

proc update_MODELPARAM_VALUE.SEG_GROUP_SWAP { MODELPARAM_VALUE.SEG_GROUP_SWAP PARAM_VALUE.SEG_GROUP_SWAP } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SEG_GROUP_SWAP}] ${MODELPARAM_VALUE.SEG_GROUP_SWAP}
}

proc update_MODELPARAM_VALUE.SEG_REVERSE_K { MODELPARAM_VALUE.SEG_REVERSE_K PARAM_VALUE.SEG_REVERSE_K } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SEG_REVERSE_K}] ${MODELPARAM_VALUE.SEG_REVERSE_K}
}

proc update_MODELPARAM_VALUE.TIMER_DELAY { MODELPARAM_VALUE.TIMER_DELAY PARAM_VALUE.TIMER_DELAY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.TIMER_DELAY}] ${MODELPARAM_VALUE.TIMER_DELAY}
}

proc update_MODELPARAM_VALUE.BT_RST_CYCLES { MODELPARAM_VALUE.BT_RST_CYCLES PARAM_VALUE.BT_RST_CYCLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BT_RST_CYCLES}] ${MODELPARAM_VALUE.BT_RST_CYCLES}
}

