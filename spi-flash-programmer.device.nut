#require "SPIFlash.class.nut:1.0.1"
#require "Serializer.class.nut:1.0.0"
#require "APA102.device.lib.nut:2.0.0"
#require "Button.class.nut:1.2.0"

class OLED_ssd1306 {
    static _displayinit = [
        "\xfd\x12",         // Unlock
        "\xae",             // Display off
        "\x15\x1c\x5b",     // Set column
        "\x75\x00\x3f",     // Set row
        "\xb3\x91",         // Display clock
        "\xca\x3f",         // Multiplex ratio
        "\xa2\x00",         // Display offset
        "\xa1\x00",         // Start line
        "\xa0\x14\x11",     // Remap format
        "\xb5\x00",         // Set GPIO
        "\xab\x01",         // Function selection
        "\xc1\x9f",         // Contrast current
        "\xc7\x0f",         // Master current
        "\xb9",             // Linear greyscale
        "\xb1\xe2",         // Phase length
        "\xd1\xa2\x20",     // Display enhancement B
        "\xbb\x1f",         // Precharge voltage
        "\xb6\x08",         // Precharge period
        "\xbe\x07",         // VCOMH
        "\xa6",             // Normal display
        "\xa9",             // Exit partial
        "\xaf",             // Display on
    ];

    _spi   = null;
    _cs_l  = null;
    _rst_l = null;
    _dc    = null;
    _state = null;
    _timer = null;
    _gen   = null;
    _callback = null;
    
    constructor(spi, cs_l, rst_l, dc){
        _spi = spi;
        _cs_l = cs_l;
        _rst_l = rst_l;
        _dc = dc;
        _state = 0;  //Display is Off

        //Initialize
        _spi.configure(SIMPLEX_TX, 10000);
        _dc.configure(DIGITAL_OUT, 0);
        _cs_l.configure(DIGITAL_OUT, 1);

        // Reset display
        _rst_l.configure(DIGITAL_OUT, 0);
        imp.sleep(0.001);
        _rst_l.write(1);
        imp.sleep(0.1);
        
        // Send init commands
        foreach(entry in _displayinit) wc(entry);
        
        // Clear screen
        wc("\x15\x1c\x5b");
        wc("\x75\x00\x3f");
    }
    

    function wc(command) {
        // Command first
        _dc.write(0);
        _cs_l.write(0);
        _spi.write(command.slice(0,1));
        _cs_l.write(1);
    
        // Data, if present
        if (command.len() > 1) {
            _dc.write(1);
            _cs_l.write(0);
            _spi.write(command.slice(1));
            _cs_l.write(1);
        }
    }

    function wd(data) {
        _dc.write(0);
        _cs_l.write(0);
        _spi.write("\x5c");
        _cs_l.write(1);
        _dc.write(1);
        _cs_l.write(0);
        _spi.write(data);
        _cs_l.write(1);
    }

    function on(){
        _state = 1;
    }
    
    function off(){
        _state = 0;
    }
    
    function clear(){
        wd(blob(256*64/2));
    }

    function draw(image){
        wd(image);
    }
    
    function invert(){
        wc("\xa7");
    }

    function uninvert(){
        wc("\xa6");
    }
    
    function cancel(){
        uninvert();
        if (_timer != null){
          imp.cancelwakeup(_timer);
          if (typeof _callback == "function") imp.wakeup(0, _callback);
        } 
        _timer = null;
    }
    
    function flash(cnt, onTime=0.33, offTime=0.66, callback=null){
        cancel();
        _callback = callback;
        resume ( _gen = function(cnt, onTime, offTime,callback){
            for(local i = 0; i < cnt; i++){
                uninvert();
                _timer = imp.wakeup(onTime, function(){resume _gen}.bindenv(this));
                yield;
                invert()
                _timer = imp.wakeup(onTime, function(){resume _gen}.bindenv(this));
                yield;
            }
            uninvert();
            if (typeof callback == "function") {
                imp.wakeup(0,callback);
            }
            _timer = null;
        }(cnt, onTime, offTime, callback));
    }
}

class OLED_compositor {
    static _res_x = 256;
    static _res_y = 64;
    static _lines = 8;   // _res_y / 8
    static _bytes = 256*64 / 2; // _res_x * _res_y / 2
    
    static SPACE_WIDTH = 6;
    
    function special(s, b) {
        if (s[0] == '#' || s[0] == '@') return [1, b];
        return [0, b];
    }

    function render(textString, background = null) {
        local _buff = blob(_bytes);
        
        local currentWord = blob(); // Build each word into a blob
        local currentString = "";   // String so we can know what it is
        local wordArray = [];       // Store those blobs in a word array
        local lineArray = [];       // Then copy them to a line array

        // Iterate through the input string and place each word into an array
        // If the word is longer than the line, split it up into multiple words so it wraps well
        foreach(charIndex, character in textString) {
            local charBytes = char2font(character);
            currentString += character.tochar();

            // If we hit a space, start a new word
            if (character == ' ') {
                wordArray.append(special(currentString, currentWord));
                currentWord = blob();               // and reset the current word
                currentString = "";
            } else {
                // If we run out of room, start a new word
                if (charBytes.len() + currentWord.len() >= _res_x) {
                    wordArray.append(special(currentString, currentWord));
                    currentWord = blob();               // and reset the current word  
                    currentString = "";
                }
                local currentChar = blob();         // Start building a character
                if (currentWord.len() > 0) {        // If this isn't the first char, add a small gap for kerning
                    currentChar.writen('\x00', 'b');
                }
                // Build the character from the included font
                foreach(byte in charBytes) {
                    currentChar.writen(byte, 'b');
                }
                currentWord.writeblob(currentChar);     // Add the current character to the current word
            }
        }
        
        // Check for hashtags
        if (currentString != "") wordArray.append(special(currentString, currentWord));

        // Write each line to a big blob to be displayed
        _buff = blob(_bytes);
        local x=0;
        local y=0;
        
        // Add background if present
        if (background) {
            _buff.writestring(background);
            y+=4;
        }
        
        foreach(word in wordArray) {
            // Will it fit on this line?
            if (x + word[1].len() + SPACE_WIDTH > _res_x) {
                // Next line
                x=0;
                if (++y > (_res_y / 8)) break;
            }
            
            // Render character
            local nibble = 0;
            if (word[0] == 1) nibble = 0x0f; else nibble = 0x06;
            local yoffset = (y*8*128);
            foreach(b in word[1]) {
                local offset = yoffset + (x/2);
                local c = (x&1) ? nibble:(nibble << 4);
                for(local p=0; p<8; p++) {
                    if (b&(1<<p)) _buff[offset] = _buff[offset] | c;
                    offset += 128;
                }
                x++;                            
            }
            
            // Space after word
            x += SPACE_WIDTH;
        }
        return _buff.tostring()
    }

    function char2font(c) {
        switch (c) {
            case ' ':  return "\x00\x00";                  // SP ----- -O--- OO-OO ----- -O--- OO--O -O--- -O---
            case '!':  return "\x5F";                      // !  ----- -O--- OO-OO -O-O- -OOO- OO--O O-O-- -O---
            case '"':  return "\x07\x03\x00\x07\x03";      // "  ----- -O--- O--O- OOOOO O---- ---O- O-O-- -----
            case '#':  return "\x24\x7E\x24\x7E\x24";      // #  ----- -O--- ----- -O-O- -OO-- --O-- -O--- -----
            case '$':  return "\x24\x2B\x6A\x12";          // $  ----- -O--- ----- -O-O- ---O- -O--- O-O-O -----
            case '%':  return "\x63\x13\x08\x64\x63";      // %  ----- ----- ----- OOOOO OOO-- O--OO O--O- -----
            case '&':  return "\x36\x49\x56\x20\x50";      // &  ----- -O--- ----- -O-O- --O-- O--OO -OO-O -----
            case '\'': return "\x03";                      // '  ----- ----- ----- ----- ----- ----- ----- -----
            //
            case '(':  return "\x3E\x41";                  // (  ---O- -O--- ----- ----- ----- ----- ----- -----
            case ')':  return "\x41\x3E";                  // )  --O-- --O-- -O-O- --O-- ----- ----- ----- ----O
            case '*':  return "\x08\x3E\x1C\x3E\x08";      // *  --O-- --O-- -OOO- --O-- ----- ----- ----- ---O-
            case '+':  return "\x08\x08\x3E\x08\x08";      // +  --O-- --O-- OOOOO OOOOO ----- OOOOO ----- --O--
            case ',':  return "\x60\xE0";                  // ,  --O-- --O-- -OOO- --O-- ----- ----- ----- -O---
            case '-':  return "\x08\x08\x08\x08\x08";      // -  --O-- --O-- -O-O- --O-- -OO-- ----- -OO-- O----
            case '.':  return "\x60\x60";                  // .  ---O- -O--- ----- ----- -OO-- ----- -OO-- -----
            case '/':  return "\x20\x10\x08\x04\x02";      // /  ----- ----- ----- ----- --O-- ----- ----- -----
            //
            case '0':  return "\x3E\x51\x49\x45\x3E";      // 0  -OOO- --O-- -OOO- -OOO- ---O- OOOOO --OOO OOOOO
            case '1':  return "\x42\x7F\x40";              // 1  O---O -OO-- O---O O---O --OO- O---- -O--- ----O
            case '2':  return "\x62\x51\x49\x49\x46";      // 2  O--OO --O-- ----O ----O -O-O- O---- O---- ---O-
            case '3':  return "\x22\x49\x49\x49\x36";      // 3  O-O-O --O-- --OO- -OOO- O--O- OOOO- OOOO- --O--
            case '4':  return "\x18\x14\x12\x7F\x10";      // 4  OO--O --O-- -O--- ----O OOOOO ----O O---O -O---
            case '5':  return "\x2F\x49\x49\x49\x31";      // 5  O---O --O-- O---- O---O ---O- O---O O---O -O---
            case '6':  return "\x3C\x4A\x49\x49\x31";      // 6  -OOO- -OOO- OOOOO -OOO- ---O- -OOO- -OOO- -O---
            case '7':  return "\x01\x71\x09\x05\x03";      // 7  ----- ----- ----- ----- ----- ----- ----- -----
            //
            case '8':  return "\x36\x49\x49\x49\x36";      // 8  -OOO- -OOO- ----- ----- ---O- ----- -O--- -OOO-
            case '9':  return "\x06\x49\x49\x29\x1E";      // 9  O---O O---O ----- ----- --O-- ----- --O-- O---O
            case ':':  return "\x6C\x6C";                  // :  O---O O---O -OO-- -OO-- -O--- OOOOO ---O- O---O
            case ';':  return "\x6C\xEC";                  // ;  -OOO- -OOOO -OO-- -OO-- O---- ----- ----O --OO-
            case '<':  return "\x08\x14\x22\x41";          // <  O---O ----O ----- ----- -O--- ----- ---O- --O--
            case '=':  return "\x24\x24\x24\x24\x24";      // =  O---O ---O- -OO-- -OO-- --O-- OOOOO --O-- -----
            case '>':  return "\x41\x22\x14\x08";          // >  -OOO- -OO-- -OO-- -OO-- ---O- ----- -O--- --O--
            case '?':  return "\x06\x01\x59\x09\x06";      // ?  ----- ----- ----- --O-- ----- ----- ----- -----
            //
            case '@':  return "\x3E\x41\x5D\x55\x1E";      // @  -OOO- -OOO- OOOO- -OOO- OOOO- OOOOO OOOOO -OOO-
            case 'A':  return "\x7E\x09\x09\x09\x7E";      // A  O---O O---O O---O O---O O---O O---- O---- O---O
            case 'B':  return "\x7F\x49\x49\x49\x36";      // B  O-OOO O---O O---O O---- O---O O---- O---- O----
            case 'C':  return "\x3E\x41\x41\x41\x22";      // C  O-O-O OOOOO OOOO- O---- O---O OOOO- OOOO- O-OOO
            case 'D':  return "\x7F\x41\x41\x41\x3E";      // D  O-OOO O---O O---O O---- O---O O---- O---- O---O
            case 'E':  return "\x7F\x49\x49\x49\x41";      // E  O---- O---O O---O O---O O---O O---- O---- O---O
            case 'F':  return "\x7F\x09\x09\x09\x01";      // F  -OOO- O---O OOOO- -OOO- OOOO  OOOOO O---- -OOO-
            case 'G':  return "\x3E\x41\x49\x49\x3A";      // G  ----- ----- ----- ----- ----- ----- ----- -----
            //
            case 'H':  return "\x7F\x08\x08\x08\x7F";      // H  O---O -OOO- ----O O---O O---- O---O O---O -OOO-
            case 'I':  return "\x41\x7F\x41";              // I  O---O --O-- ----O O--O- O---- OO-OO OO--O O---O
            case 'J':  return "\x30\x40\x40\x40\x3F";      // J  O---O --O-- ----O O-O-- O---- O-O-O O-O-O O---O
            case 'K':  return "\x7F\x08\x14\x22\x41";      // K  OOOOO --O-- ----O OO--- O---- O---O O--OO O---O
            case 'L':  return "\x7F\x40\x40\x40\x40";      // L  O---O --O-- O---O O-O-- O---- O---O O---O O---O
            case 'M':  return "\x7F\x02\x04\x02\x7F";      // M  O---O --O-- O---O O--O- O---- O---O O---O O---O
            case 'N':  return "\x7F\x02\x04\x08\x7F";      // N  O---O -OOO- -OOO- O---O OOOOO O---O O---O -OOO-
            case 'O':  return "\x3E\x41\x41\x41\x3E";      // O  ----- ----- ----- ----- ----- ----- ----- -----
            //
            case 'P':  return "\x7F\x09\x09\x09\x06";      // P  OOOO- -OOO- OOOO- -OOO- OOOOO O---O O---O O---O
            case 'Q':  return "\x3E\x41\x49\x31\x5E";      // Q  O---O O---O O---O O---O --O-- O---O O---O O---O
            case 'R':  return "\x7F\x09\x09\x19\x66";      // R  O---O O---O O---O O---- --O-- O---O O---O O-O-O
            case 'S':  return "\x26\x49\x49\x49\x32";      // S  OOOO- O-O-O OOOO- -OOO- --O-- O---O O---O O-O-O
            case 'T':  return "\x01\x01\x7F\x01\x01";      // T  O---- O--OO O--O- ----O --O-- O---O O---O O-O-O
            case 'U':  return "\x3F\x40\x40\x40\x3F";      // U  O---- O--O- O---O O---O --O-- O---O -O-O- O-O-O
            case 'V':  return "\x1F\x20\x40\x20\x1F";      // V  O---- -OO-O O---O -OOO- --O-- -OOO- --O-- -O-O-
            case 'W':  return "\x3F\x40\x3C\x40\x3F";      // W  ----- ----- ----- ----- ----- ----- ----- -----
            //
            case 'X':  return "\x63\x14\x08\x14\x63";      // O  O---O O---O OOOOO -OOO- ----- -OOO- --O-- -----
            case 'Y':  return "\x07\x08\x70\x08\x07";      // Y  O---O O---O ----O -O--- O---- ---O- -O-O- -----
            case 'Z':  return "\x61\x51\x49\x45\x43";      // Z  -O-O- O---O ---O- -O--- -O--- ---O- O---O -----
            case '[':  return "\x7F\x41\x41";              // [  --O-- -O-O- --O-- -O--- --O-- ---O- ----- -----
            case '\\': return "\x02\x04\x08\x10\x20";      // \  -O-O- --O-- -O--- -O--- ---O- ---O- ----- -----
            case ']':  return "\x41\x41\x7F";              // ]  O---O --O-- O---- -O--- ----O ---O- ----- -----
            case '^':  return "\x04\x02\x01\x02\x04";      // ^  O---O --O-- OOOOO -OOO- ----- -OOO- ----- OOOOO
            case '_':  return "\x40\x40\x40\x40\x40";      // _  ----- ----- ----- ----- ----- ----- ----- -----
            //
            case '`':  return "\x03\x07";                  // `  -OO-- ----- O---- ----- ----O ----- --OOO -----
            case 'a':  return "\x20\x54\x54\x54\x78";      // a  -OO-- ----- O---- ----- ----O ----- -O--- -----
            case 'b':  return "\x7F\x44\x44\x44\x38";      // b  --O-- -OOO- OOOO- -OOO- -OOOO -OOO- -O--- -OOOO
            case 'c':  return "\x38\x44\x44\x44";          // c  ----- ----O O---O O---- O---O O---O OOOO- O---O
            case 'd':  return "\x38\x44\x44\x44\x3F";      // d  ----- -OOOO O---O O---- O---O OOOO- -O--- O---O
            case 'e':  return "\x38\x54\x54\x54\x08";      // e  ----- O---O O---O O---- O---O O---- -O--- -OOOO
            case 'f':  return "\x08\x7E\x09\x09\x01";      // f  ----- -OOOO OOOO- -OOO- -OOOO -OOO- -O--- ----O
            case 'g':  return "\x18\xA4\xA4\xA4\x7C";      // g  ----- ----- ----- ----- ----- ----- ----- -OOO-
            //
            case 'h':  return "\x7F\x04\x04\x04\x78";      // h  O---- -O--- ----O O---- O---- ----- ----- -----
            case 'i':  return "\x7D\x40";                  // i  O---- ----- ----- O---- O---- ----- ----- -----
            case 'j':  return "\x40\x80\x80\x84\x7D";      // j  OOOO- -O--- ---OO O--O- O---- OO-O- OOOO- -OOO-
            case 'k':  return "\x7F\x10\x28\x44";          // k  O---O -O--- ----O O-O-- O---- O-O-O O---O O---O
            case 'l':  return "\x7F\x40";                  // l  O---O -O--- ----O OO--- O---- O-O-O O---O O---O
            case 'm':  return "\x7C\x04\x18\x04\x78";      // m  O---O -O--- ----O O-O-- O---- O---O O---O O---O
            case 'n':  return "\x7C\x04\x04\x04\x78";      // n  O---O -OO-- O---O O--O- OO--- O---O O---O -OOO-
            case 'o':  return "\x38\x44\x44\x44\x38";      // o  ----- ----- -OOO- ----- ----- ----- ----- -----
            //
            case 'p':  return "\xFC\x44\x44\x44\x38";      // p  ----- ----- ----- ----- ----- ----- ----- -----
            case 'q':  return "\x38\x44\x44\x44\xFC";      // q  ----- ----- ----- ----- -O--- ----- ----- -----
            case 'r':  return "\x44\x78\x44\x04\x08";      // r  OOOO- -OOOO O-OO- -OOO- OOOO- O--O- O---O O---O
            case 's':  return "\x48\x54\x54\x54\x20";      // s  O---O O---O -O--O O---- -O--- O--O- O---O O---O
            case 't':  return "\x04\x3E\x44\x44\x20";      // t  O---O O---O -O--- -OOO- -O--- O--O- O---O O-O-O
            case 'u':  return "\x3C\x40\x40\x7C";          // u  O---O O---O -O--- ----O -O--O O--O- -O-O- OOOOO
            case 'v':  return "\x1C\x20\x40\x20\x1C";      // v  OOOO- -OOOO OOO-- OOOO- --OO- -OOO- --O-- -O-O-
            case 'w':  return "\x3C\x60\x30\x60\x3C";      // w  O---- ----O ----- ----- ----- ----- ----- -----
            //
            case 'x':  return "\x44\x28\x10\x28\x44";      // x  ----- ----- ----- ---OO --O-- OO--- -O-O- -OO--
            case 'y':  return "\x9C\xA0\x60\x3C";          // y  ----- ----- ----- --O-- --O-- --O-- O-O-- O--O-
            case 'z':  return "\x64\x54\x54\x4C";          // z  O---O O--O- OOOO- --O-- --O-- --O-- ----- O--O-
            case '{':  return "\x08\x3E\x41\x41";          // {  -O-O- O--O- ---O- -OO-- ----- --OO- ----- -OO--
            case '|':  return "\x77";                      // |  --O-- O--O- -OO-- --O-- --O-- --O-- ----- -----
            case '}':  return "\x41\x41\x3E\x08";          // }  -O-O- -OOO- O---- --O-- --O-- --O-- ----- -----
            case '~':  return "\x02\x01\x02\x01";          // ~  O---O --O-- OOOO- ---OO --O-- OO--- ----- -----
            case '_':  return "\x06\x09\x09\x06";          // _  ----- OO--- ----- ----- ----- ----- ----- -----
            //
            case '\t': return "\x00\x00\x00\x00\x00\x00\x00\x00";      // Tab
            case '\n': return "\x24\x76\x7F\xF7\xE0\xE0\x70\x70\x20";  // Duck
            default:   return "\x00\x00\x00\x00\x00";                  // Blank 
        }
    }
}

// Set up display
oled <- OLED_ssd1306(hardware.spiGJKL, hardware.pinL, hardware.pinN, hardware.pinM);
oled_compositor <- OLED_compositor();

// Source image
header <- null;

// What we're fetching (when we are populating the local cache)
fetch <- {}
const SPI_004_SIZE = 0x0c2000;
const SPI_005_SIZE = 0x360000;
const SPI_CLOUDIFY_004_SIZE = 0x185000;

// Table of impOS URL, size and name
impOSTable <-  { "imp004" : { "path":"https://milewski.org/imp/spi_image_004_8m.bin", "trim":SPI_004_SIZE, "name":"004_8m" },
                   "imp005" : { "path":"https://milewski.org/imp/imp005-release-36.10-production-flashcaps.rom", "trim":SPI_005_SIZE, "name":"005_36.10" },
                   "private" : { "path":"https://milewski.org/imp/imp005-release-36.10-production-flashcaps.rom", "trim":SPI_005_SIZE, "name":"none" } };

// ----------------------------------------------------------------------------------------------

const LED_MAX = 16;

// Instantiate LED array with 8 pixels
pixels <- APA102(null, 8, hardware.pinE, hardware.pinD);
pixels.draw();

// Boost source spi speed
actualrate <- hardware.spiflash.setspeed(12000000);
hardware.spiflash.enable();
server.log(format("Cache SPI chipid : %06x",hardware.spiflash.chipid()));
server.log(format("Cache SPI rate   : %.2fMHz", actualrate / 1000000.0));
server.log(format("Cache SPI size   : %.2fMB", hardware.spiflash.size() / (1024.0*1024)))

// screen variables
file_name <- "" // name of currently stored impOS image
// main menu display template
main_image <- "Current impOS image: %s\t\t\t\t\t \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Select your impOS image:\t\t\t\t\t\t\t\t\t\t\t\t imp004 %s\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t imp005 %s\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t private cloud %s";
display_image <- ""
programming_image <- ""
local display_arrow = array(3);
display_arrow = ["<", "", ""]

//check_cache() will check to see if there is an image stored in the spi-flasher
function check_cache(){
// Check we have a valid image to program in the cache SPI
    local dataBlob = hardware.spiflash.read(0x00, 3);
    local len = dataBlob.readn('w');
    
    if (len == 0xffff || len == 0x0000) {
        server.log("No cache header found; you need to populate this");
        fetch_flash_image = true;
        display_image = format(main_image, file_name, display_arrow[0], display_arrow[1], display_arrow[2]);
      
       oled.draw(oled_compositor.render(format(display_image)));
    } else {
        // Found a serialized header, read the data and parse
        dataBlob.seek(0, 'e');
        hardware.spiflash.readintoblob(0x03, dataBlob, len);
        header = Serializer.deserialize(dataBlob);
        file_name = header.name;
        server.log(format("Cached image     : 0x%x byte image of %s", header.trim, header.path));
       // oled.draw(oled_compositor.render(format("image: %s (%dkB)", header.path, header.trim/1024)));
       
       display_image = format(main_image, file_name, display_arrow[0], display_arrow[1], display_arrow[2]);
      
       oled.draw(oled_compositor.render(format(display_image)));
    }

}

// Configure target SPI bus
ls_en <- hardware.pinF;
ls_en.configure(DIGITAL_OUT,1);
spif <- hardware.spiAHSR;

actualrate <- spif.configure(CLOCK_IDLE_LOW | MSB_FIRST, 12000);
cs <- hardware.pinR;

spiFlash <- SPIFlash(spif, cs);
// ----------------------------------------------------------------------------------------------
// Download cloud image into system flash
// ----------------------------------------------------------------------------------------------

target <- hardware.spiflash;
offset <- 0;
done <- 0;
fetch_percent <- 0;
fetch_size <- 0;
pixnum <- 7;

// fetch_image() will fetch the selected image from the agent and store it in on board flash memory
function fetch_image(){
    if (true) {
        agent.on("flash", function(v) {

            done = 0;
            
            server.log(format("Writing %d bytes at %08x", v.data.len(), v.address)); 
            
            target.enable();
        
            server.log(v.percent);
            if(file_name == "004_8m"){ //have to do this to format the screen for the smaller url
                oled.draw(oled_compositor.render(format("Fetching image from: "+ fetch.path + "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Writing %d bytes at %08x \t\t\t\t\t\t\t\t %d%% complete", v.data.len(), v.address, v.percent)));
            }else{
                oled.draw(oled_compositor.render(format("Fetching image from: "+ fetch.path + "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Writing %d bytes at %08x \t\t\t\t\t\t\t\t %d%% complete", v.data.len(), v.address, v.percent)));
                
            }
            pixels.fill([0,0,0]).draw();
            
            pixels.set(pixnum, [0,0,10]).draw();
            
            pixnum>0 ? pixnum-- : pixnum=7; //Move pixel location
            
            for (local i = v.address ; i < (v.data.len() + v.address) ; i += 4096) {
                target.erasesector(4096+i);
            }
            
            local res = target.write(4096+v.address, v.data, SPIFLASH_POSTVERIFY);
            target.disable();
            if (res != 0) {
                server.log("Write returned " + res);
            } else {
                // We done yet?
                if ((v.address+v.data.len()) >= fetch.trim) {
                    // Fetched the entire image, write the header at the start
                    server.log("Fetch completed, writing header");
                    oled.draw(oled_compositor.render("Fetch complete! \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Press ENTER to program spi flash \t\t\t\t\t\t\t Press SELECT to return to main menu"));

                    res = target.write(0, Serializer.serialize(fetch), SPIFLASH_POSTVERIFY);
                    if (res != 0) {
                        server.log("Unable to write local cache header");
                        return;
                    }
                    server.log("Done!");
                    
                } else {
                    // Next block
                    agent.send("ack", v.data.len());
                }
            }
        });
        
        // Boost source spi speed
        hardware.spiflash.setspeed(12000000);
        hardware.spiflash.enable();
        server.log("infetch-wakup");

        // Start programming in 1s
        imp.wakeup(1, function() {
            // Erase first 4k page; we write the header once the full fetch is done
            target.erasesector(0);
    
            // Start fetch process
            agent.send("start", fetch);
        });
        

        return
    }
}

// Target device
chipid <- -1;
size <- -1;

//id_chip checks to see if the provided chip is known
function id_chip() { 
    // Identify the chip we're programming
    chipid = -1;
    size = -1;
    try {
        spiFlash.enable();
        chipid = spiFlash.chipid();
        spiFlash.disable();
    } catch(e) {
        server.log(e);
    }
    
    server.log(format("Target SPI ID    : %06x", chipid));
    server.log(format("Target SPI rate  : %.2fMHz", actualrate / 1000.0));
    
    // Identify chip
    switch(chipid) {
        case 0x1f8501: // Adesto 25SF081 1MB
            size = 1;
            server.log("Adesto 25SF081 1MB")
            break;
        case 0x1f8601: // Adesto 25SF161 2MB
            size = 2;
            server.log("Adesto 25SF161 2MB")
            break;
        case 0x0e4015: // FMD FT25H16S-RT
            size = 2;
            server.log("FMD FT25H165-RT 2MB")
            break;
        case 0x014017: // Spansion S25FL164 8MB
            size = 8;
            server.log("Spansion S25FL164 8MB")
            spiFlash.enable();
            cs.write(0);
            server.log(spif.writeread("\x35\x00"));            
            cs.write(1);
            break;
        case 0xc22016: // macronix MX25L3206EM2I-12G 4MB
            size = 4;
            server.log("Macronix MX25L3206EM2I 4MB")
            break;
        case 0xc22017: // macronix 8MB
            size = 8;
            server.log("Macronix MX25L6445EM2I-10G 8MB")
            break;
        case 0xc22018: // macronix 16MB
            size = 16;
            server.log("Macronix 16MB")
            break;
        case 0xc22817: // Macronix MX25R6435FM2IH0 8MB
            size = 8;
            server.log("Macronix MX25R6435FM2IH0 8MB")
            break;
        case 0x016017: // Spansion S25FL064 8MB
            size = 8;
            server.log("Spansion S25FL064 8MB");
            break;
        case 0x016018: // Spansion S25FL128LAGMFI010 16MB
            size = 16;
            server.log("Spansion S25FL128LAGMFI010 16MB");
            break;
        case 0xef4016: // Winbond W25Q32JVSSIQ
            size = 4;
            server.log("Spansion W25Q32JVSSIQ 4MB");
            break;
        case 0x9d6017: // ISSI IS25LP064A-JBLE
            size = 8;
            server.log("Spansion IS25LP064A-JBLE 8MB");
            break;
        case 0x1f4800: // Adesto AT25DF641A-SH-B
            size = 8;
            server.log("Adesto AT25DF641A-SH-B 8MB");
            
            // This chip comes by default totally protected.
            // Issue a global unprotect command
            spiFlash.enable();
            cs.write(0); server.log(spif.writeread("\x06")); cs.write(1);
            cs.write(0); server.log(spif.writeread("\x01\x00")); cs.write(1);   
            spiFlash.disable();
            break;
        case 0x1f3217: // Adesto AT25SF641-SUB
            size = 8;
            server.log("Adesto AT25SF641-SUB 8MB");
            break;
        case 0xef4015: // Winbond W25Q16BV
            size = 2;
            server.log("Winbond W25Q16BV 2MB");
            break;
        default:
            // Unknown chip ID
            server.log("unknown flash");
            oled.draw(oled_compositor.render("Unknown flash... \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Please make sure you are using a supported flash \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Press ENTER to program again \t\t\t\t\t\t\t Press SELECT to return to main menu"));

            pixels.set(7, [LED_MAX, 0, 0]).draw();
           return false;
    }

    // We know this chip
    pixels.set(7, [0, LED_MAX, 0]).draw();
    return true;
}

disp_prog_img <- ""
percent <- 0;
pix_num_off <- 0;

//copyFlash copies the impOS image from the on-board flash into the external flash
function copyflash(length, erase = true) {
    server.log(format("programming 0x%x bytes%s", length, (erase?" (with erase)":"")));

    local offset = 0;
    local maxchunk = erase?4096:32768;
    
    while(offset < length) { // loop until programming complete
        local chunk = (length - offset);
        if (chunk > maxchunk) chunk = maxchunk;
        if (erase) spiFlash.erasesector(offset); // erase sector before write if erase enabled
        
        // Show status every 256kB
        percent = 100*offset/length;

        if ((offset & 0x3ffff) == 0) {
            server.log(format("Programming %08x (%d%%)", offset, (percent)));
        }
        
        disp_prog_img = format("%s \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Programming: %d%%", programming_image,(percent));
           
        oled.draw(oled_compositor.render(disp_prog_img));
        
        local res = spiFlash.write(offset, hardware.spiflash.read(4096+offset, chunk), SPIFLASH_POSTVERIFY); //spi flash write
        if (res != 0) {
            return res;
        }
        
        //Update LED percent meter
        if (percent < 12.5){
            pix_num_off = 7;
            server.log(percent);
        } else if ((percent>=12.5) && (percent<25)){
            pix_num_off = 6;
            server.log(percent);
        } else if ((percent>=25) && (percent<37.5)){
            pix_num_off = 5;
            server.log(percent);
        } else if ((percent>=37.5) && (percent<50)){
            pix_num_off = 4;       
            server.log(percent);
        } else if ((percent>=50) && (percent<62.5)){
            pix_num_off = 3;    
            server.log(percent);
        } else if ((percent>=62.5) && (percent<75)){
            pix_num_off = 2;  
            server.log(percent);
        } else if ((percent>=75) && (percent<87.5)){
            pix_num_off = 1;  
            server.log(percent);
        } else if ((percent>=99) && (percent<=100)){
            pix_num_off = 0;  
            server.log(percent);
        }
       
        pixels.fill([0,0,10], pix_num_off, 7).draw();
        
        offset += chunk;
    }
       
    return 0;   
}

//cycle() wraps copyflash() with error handling and determines whether to program with or without erase
function cycle() {
    
    // Optionally check that target device is blank
    if (false) {
        server.log("Blank check");
        
        local checksize = 4096;
        
        // First make a blank sector into a string; this allows us to do a fast compare
        local blank = blob(checksize);
        for(local address = 0; address < blank.len(); address++) blank[address] = 0xff;
        local blankstr = blank.tostring();
        blank = null;

        spiFlash.enable();
        
        for(local address = 0; address < (1024*1024*size); address += checksize) {
            local sector = spiFlash.read(address, checksize);
            if (sector.tostring() == blankstr) {
            } else {
                server.log(format("address %08x:", address))
                server.log(sector);
            }
        }
        
        spiFlash.disable();
        server.log("Blank check complete");
        return;
    }
    
    if (!id_chip()) return; //make sure the flash is a known chip
    server.log("in cycle");
    // Program image from local copy
    local start = time();
    
    spiFlash.enable();
    
    programming_image = "Flash blank, programming without erase";
    
    try{ //In case spi flash chip fails or is removed before programming is complete
    
        if (copyflash(header.trim, false)) {// Try without erase first
            // Failed, try again with erase
            programming_image = "Flash not blank, programming with erase";
            local res = copyflash(header.trim, true);
        
            if (res != 0) {
                server.log("program error "+res);
                throw "write error!";
            }
        
        }
    } catch(exception){
        
        //turn led red
        pixels.fill([0,0,0]).draw();
        pixels.set(7,[10,0,0]).draw();
        
        server.error(exception);
        oled.draw(oled_compositor.render("Programming failed... \t\t\t\t\t\t\t\t\t\t\t\t Check that flash chip is properly seated. \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Press ENTER to program again \t\t\t\t\t\t\t Press SELECT to return to main menu"));

        return;
    }
   
    spiFlash.disable();
    server.log("programmed in "+(time()-start)+"s");
    oled.draw(oled_compositor.render("Programming complete! \t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t Press ENTER to program again \t\t\t\t\t\t\t Press SELECT to return to main menu"));
   
   
    pixels.fill([0,0,0]).draw(); //clear leds
    
    pixels.set(7,[0,10,0]).draw(); //set left most led green
}

/**************************************************************************************************************
 * Program begins
 **************************************************************************************************************/

// Press enter to program
check_cache(); //update name variable and initial display write
selectCount <- 1;

//Select button control function, moves the select arrow
select <- Button(hardware.pinB, DIGITAL_IN_PULLUP, Button.NORMALLY_HIGH,
    function () {
        
        pixels.fill([0,0,0]).draw();
        if (selectCount >= 3) selectCount =1;
        else selectCount++;

        server.log(selectCount);
        if(selectCount == 1){
            display_arrow = ["<", "", ""];
        } else if (selectCount == 2){
            display_arrow = ["", "<", ""];
        } else if (selectCount == 3){
            display_arrow = ["", "", "<"];
        }
        
        display_image = format(main_image, file_name, display_arrow[0], display_arrow[1], display_arrow[2]);

        oled.draw(oled_compositor.render(display_image));
    }
);

name <- "";

//Enter button control function, after an image is selected this will check if a fetch is needed, otherwise will start flashing
enter <- Button(hardware.pinC, DIGITAL_IN_PULLUP, Button.NORMALLY_HIGH,
    function() {

        if (selectCount == 1){

            fetch = impOSTable.imp004;
            if (file_name == fetch.name){
                cycle(); //if stored image is the same as requested then go straight to programming flash chip
            } else {
                fetch_image(); //pull new image into flash
                check_cache(); //update header variables and update display
            }        
            
            file_name = fetch.name;

        } else if (selectCount == 2){

            fetch = impOSTable.imp005;

             if (file_name == fetch.name){
                cycle(); //if stored image is the same as requested then go straight to programming flash chip
            } else {
                fetch_image(); //pull new image into flash
                check_cache(); //update header variables and update display
            }        
            
            file_name = fetch.name;

        } else if (selectCount == 3){
          
            fetch = impOSTable.private;

            if (file_name == fetch.name){
                cycle(); //if stored image is the same as requested then go straight to programming flash chip
            } else {
                fetch_image(); //pull new image into flash
                check_cache(); //update header variables and update display
            }          
            
            file_name = fetch.name;
        }

        display_image = format(main_image, file_name, display_arrow[0], display_arrow[1], display_arrow[2]);

    }

);
