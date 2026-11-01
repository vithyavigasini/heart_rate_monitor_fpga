# Heart Rate Monitor on FPGA (DE2-115)

Mini project for Digital System Design with FPGA.



A pulse sensor (HW-827) is read through an ADS1115 ADC over I2C. The FPGA detects each heartbeat, counts the beats over 60 seconds and shows the BPM and the heart condition on a 1.3 inch I2C OLED:

* BRADY: below 60 BPM
* NORMAL: 60 to 100 BPM
* TACHY: above 100 BPM

The BPM is also shown on HEX2 to HEX0, and a buzzer gives a beep on every beat or an alarm when the rate is abnormal.

## Files

|File|Description|
|-|-|
|pulse\_monitor\_final.v|Verilog code of all the modules (top-level entity: top\_main)|
|pins.tcl|Pin assignments for the DE2-115 board|
|timing.sdc|50 MHz clock constraint|
|tb\_top\_main.v|Testbench for the complete design|
|i2c\_slave\_models.v|Simulation models of the OLED and the ADS1115|
|wiring\_diagram.png|Wiring between the board, ADC, OLED, sensor and buzzer|

## Hardware

* Terasic DE2-115 (Cyclone IV E EP4CE115F29C7)
* HW-827 pulse sensor
* ADS1115 16-bit ADC module
* 1.3 inch I2C OLED (128 x 64)
* Passive buzzer

## Wiring

!\[wiring](wiring\_diagram.png)

|GPIO header pin|Connected to|
|-|-|
|1|OLED SDA|
|2|OLED SCL|
|3|ADS1115 SDA|
|4|ADS1115 SCL|
|5|Buzzer (+)|
|29 (3.3 V)|OLED VCC, ADS1115 VDD, sensor (+)|
|30 (GND)|All GND pins, ADS1115 ADDR, buzzer (-)|

The sensor signal (S) goes to ADS1115 input A0. Header pin 11 (5 V) is not used. Jumper JP6 should be on pins 7-8 (3.3 V).

## Building in Quartus

1. Create a new project, add pulse\_monitor\_final.v and select the device EP4CE115F29C7.
2. Add timing.sdc to the project.
3. Run pins.tcl from Tools > Tcl Scripts. This also sets top\_main as the top-level entity.
4. Compile and program the board.

## Board controls

|Control|Function|
|-|-|
|KEY0|Reset|
|SW0|Buzzer mode (down: beep on every beat, up: alarm when BRADY or TACHY)|
|SW1|Mute the buzzer|
|LEDG0|Blinks on every detected beat|
|LEDG1 / LEDG2|OLED / ADC responding|
|LEDG5 / LEDG6 / LEDG7|BRADY / NORMAL / TACHY|

## Simulation

The testbench uses Icarus Verilog:

```
iverilog -g2012 -s tb\_top\_main -o sim.vvp tb\_top\_main.v i2c\_slave\_models.v pulse\_monitor\_final.v
vvp sim.vvp
```

It runs three minutes of simulated time (72 BPM, then 120 BPM, then 45 BPM) and prints the BPM, the condition and the OLED screen for each minute. The result should end with `ALL PASSED`.

