
## SPI Flash Programmer ##

The SPI flash programmer allows users to program the impOS for imp004m and imp005 into a SPI flash chip. You will need to copy the agent and device code from the git repository into your ImpCentral account and program it to the SPI Flash programmer.
![SPI Flash Programmer](https://github.com/jackziemba/SPI-Flasher/blob/master/images/IMG_20180830_174348.jpg)
## Device Usage ##

Once the code is loaded on the device you will see the main menu on the display. Select between imp004, imp005 or private cloud and press *ENTER*. The device will start downloading the impOS image from the cloud and the screen will display the status. Once this is complete you can press *ENTER* to begin flashing your SPI flash chip. The *SELECT* button can be used to return to the main menu. If you are in the main menu you can program a SPI flash chip again without downloading the image by selecting the image that is already stored. The stored image is displayed at the top of the screen. 


 ### Buttons ####
 The SPI flash programmer has two buttons, *SELECT* and *ENTER*. *SELECT* is used to navigate the menu and *ENTER* is used to select the options. 

### Connectors ###

The SPI flash programmer supports 8-WDFN, 8-SOP, narrow 8-SOP and has a 10 pin J-Tag connector for external connections. Identify which socket matches your SPI flash chip and insert the chip. If your SPI flash is already soldered to a board then use the 10 Pin J-Tag connector. The pinout is labelled on the back of the board. This pinout is labelled to match the [Sparkfun Bus Pirate Cable](https://www.sparkfun.com/products/9556).
 
 
 ### Toggle Switches ###
 The device has two toggle switches, *Ext En* and *3V3 Ext*. The *Ext En* switch is used to enable the 10 Pin J-Tag connector. The *3V3 En* switch will enable power to the 3V3 pin on the 10 Pin J-Tag connector.
 
 ### Footswitch ###
 A 3.5mm jack is available to use a footswitch in place of the *SELECT* button.


## Assembly ##

### PCB ###
Download the [gerber](https://github.com/jackziemba/SPI-Flasher/blob/master/spi_flash_programmer_gerbers.zip) files. You will need to send these to a PCB manufacturer.

### Bill of Materials ###
The [BOM](https://github.com/jackziemba/SPI-Flasher/blob/master/spi_flash_programmer_BOM.csv) contains a list of all the components that can be ordered from [digikey](https://www.digikey.com/).


### IC sockets ###
The IC sockets are available from [www.test-socket.com](http://www.test-socket.com/#8)

8-WDFN - 08QN12T16050, 8-SOP - 652C0082211W003, 8-Narrow SOP - 652B0082211-002


### Display ###

The display is available from [BuyDisplay](https://www.buydisplay.com/default/oled-display-arduino-3-2-inch-graphic-serial-module-256x64-blue-on-black).

### Stacked Acrylic Enclosure ###
These pieces can be laser cut using the [.svg](https://github.com/jackziemba/SPI-Flasher/blob/master/spi-flasher-acrylic.zip) files in the repository. The enclosure is not a necessary component to the SPI flash programmers functionality.

