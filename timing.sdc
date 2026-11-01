# timing.sdc -- tells Quartus the board clock is 50 MHz (20 ns)
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty
