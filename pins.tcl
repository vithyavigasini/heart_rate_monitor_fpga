# ============================================================
# pins.tcl  --  DE2-115 pin assignments for the FINAL project
#
# Quartus:  Tools -> Tcl Scripts -> pins.tcl -> Run
# Top-level = top_main (with ADC).  For the no-ADC backup change the
# TOP_LEVEL_ENTITY line below to top_main_direct and run this again.
# Pin numbers checked against the DE2-115 User Manual.
# Names a design does not use are simply ignored.
# ============================================================

set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE115F29C7
set_global_assignment -name TOP_LEVEL_ENTITY top_main
set_global_assignment -name SDC_FILE timing.sdc

# ---------- 50 MHz clock and push buttons ----------
set_location_assignment PIN_Y2   -to CLOCK_50
set_location_assignment PIN_M23  -to KEY[0]
set_location_assignment PIN_M21  -to KEY[1]
set_location_assignment PIN_N21  -to KEY[2]
set_location_assignment PIN_R24  -to KEY[3]

# ---------- GPIO header JP5 ----------
#  header pin 1 = GPIO[0] = OLED SDA     header pin 2 = GPIO[1] = OLED SCL
#  header pin 3 = GPIO[2] = ADC  SDA     header pin 4 = GPIO[3] = ADC  SCL
#  header pin 5 = GPIO[4] = BUZZER
#  header pin 29 = 3.3 V                 header pin 30 = GND
set_location_assignment PIN_AB22 -to OLED_SDA
set_location_assignment PIN_AC15 -to OLED_SCL
set_location_assignment PIN_AB21 -to ADC_SDA
set_location_assignment PIN_Y17  -to ADC_SCL
# the header runs at 3.3 V (jumper JP6 on pins 7-8, the default)
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to OLED_SDA
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to OLED_SCL
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ADC_SDA
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to ADC_SCL
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to OLED_SDA
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to OLED_SCL
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to ADC_SDA
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to ADC_SCL

# buzzer on header pin 5 (GPIO[4])
set_location_assignment PIN_AC21 -to BUZZER
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BUZZER

# slide switches: SW0 = buzzer mode, SW1 = mute
set_location_assignment PIN_AB28 -to SW[0]
set_location_assignment PIN_AC28 -to SW[1]

# backup design (top_main_direct.v): pulse sensor S straight into header pin 3
set_location_assignment PIN_AB21 -to PULSE_IN
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to PULSE_IN

# ---------- red LEDs ----------
set_location_assignment PIN_G19  -to LEDR[0]
set_location_assignment PIN_F19  -to LEDR[1]
set_location_assignment PIN_E19  -to LEDR[2]
set_location_assignment PIN_F21  -to LEDR[3]
set_location_assignment PIN_F18  -to LEDR[4]
set_location_assignment PIN_E18  -to LEDR[5]
set_location_assignment PIN_J19  -to LEDR[6]
set_location_assignment PIN_H19  -to LEDR[7]
set_location_assignment PIN_J17  -to LEDR[8]
set_location_assignment PIN_G17  -to LEDR[9]
set_location_assignment PIN_J15  -to LEDR[10]
set_location_assignment PIN_H16  -to LEDR[11]
set_location_assignment PIN_J16  -to LEDR[12]
set_location_assignment PIN_H17  -to LEDR[13]
set_location_assignment PIN_F15  -to LEDR[14]
set_location_assignment PIN_G15  -to LEDR[15]
set_location_assignment PIN_G16  -to LEDR[16]
set_location_assignment PIN_H15  -to LEDR[17]

# ---------- green LEDs ----------
set_location_assignment PIN_E21  -to LEDG[0]
set_location_assignment PIN_E22  -to LEDG[1]
set_location_assignment PIN_E25  -to LEDG[2]
set_location_assignment PIN_E24  -to LEDG[3]
set_location_assignment PIN_H21  -to LEDG[4]
set_location_assignment PIN_G20  -to LEDG[5]
set_location_assignment PIN_G22  -to LEDG[6]
set_location_assignment PIN_G21  -to LEDG[7]
set_location_assignment PIN_F17  -to LEDG[8]

# ---------- 7-segment displays HEX0, HEX1, HEX2 ----------
set_location_assignment PIN_G18  -to HEX0[0]
set_location_assignment PIN_F22  -to HEX0[1]
set_location_assignment PIN_E17  -to HEX0[2]
set_location_assignment PIN_L26  -to HEX0[3]
set_location_assignment PIN_L25  -to HEX0[4]
set_location_assignment PIN_J22  -to HEX0[5]
set_location_assignment PIN_H22  -to HEX0[6]
set_location_assignment PIN_M24  -to HEX1[0]
set_location_assignment PIN_Y22  -to HEX1[1]
set_location_assignment PIN_W21  -to HEX1[2]
set_location_assignment PIN_W22  -to HEX1[3]
set_location_assignment PIN_W25  -to HEX1[4]
set_location_assignment PIN_U23  -to HEX1[5]
set_location_assignment PIN_U24  -to HEX1[6]
set_location_assignment PIN_AA25 -to HEX2[0]
set_location_assignment PIN_AA26 -to HEX2[1]
set_location_assignment PIN_Y25  -to HEX2[2]
set_location_assignment PIN_W26  -to HEX2[3]
set_location_assignment PIN_Y26  -to HEX2[4]
set_location_assignment PIN_W27  -to HEX2[5]
set_location_assignment PIN_W28  -to HEX2[6]

export_assignments
