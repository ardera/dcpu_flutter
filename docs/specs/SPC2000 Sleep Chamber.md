```
NE_SPC2000 v1.1
    
                                     \ |  ___ 
                                   |\ \|  ___  
                                   | \

                                 NYA ELEKTRISKA
                             innovation information




DCPU-16 Hardware Info:
    Name: SPC2000 - Suspension Chamber 2000
    ID: 0x40e41d9d, version: 0x005e
    Manufacturer: 0x1c6c8b36 (NYA_ELEKTRISKA)


======================= WARNING WARNING WARNING WARNING ========================    
  FERMIONS NEAR THE ACTIVATION RADIUS ARE CATASTROPHICALLY DESTROYED. DO NOT
  USE NEAR EARTH OR MARS OR ANY OTHER FUTURE EARTH COLONIES. DO NOT TAMPER
  WITH THE VACUUM DETECTOR. DO NOT USE IN AN INHOMOGENEOUS GRAVITATIONAL FIELD.
  DO NOT USE WHEN ROTATING. DO NOT USE WHEN ACCELERATING. ABSOLUTELY NO WARRANTY
  IS PROVIDED, USE AT YOUR OWN RISK.
  THE ZEF882 INCLUDED IN THIS SUSPENSION CHAMBER IS ILLEGAL IN ALL COUNTRIES.
======================= WARNING WARNING WARNING WARNING ========================    

Description:
    The SPC2000 is a deep sleep cell based on the ZEF882 time dilation field
    generator (available from Polytron Corporation Incorporated).
    It provides safe and nearly instantaneous time passage, making long journeys
    in space much easier on the passengers, and allowing cargo to reach its
    destination with minimal aging occurring.
    Due to the nature of the ZEF882, it affects the entire vessel (50 meter
    radius, and will only engage in a near vacuum. Once the SPC2000 is active,
    the vessel will be almost nowhere to an external observer, and detection of
    the vessel is beyond unlikely.
    Because of the strong extra-dimensional acceleration and non-linear temporal
    distortion that occurs, it's highly recommended that passengers are strapped
    in and asleep when triggering the SCP2000.
    

Improvements:
    * Added the ability to set the unit to skip to something other than the
      default setting of milliseconds.
    
    
Interrupt behavior:
    When a HWI is received by the SPC2000, it reads the A register and does one
    of the following actions:
    
    0: GET_STATUS
       Sets the C register to 1 if the SPC2000 is ready to trigger. If it's not,
       the B register is set to one of the following values:
          0x0000: ######################## - EVACUATE VESSEL IMMEDIATELY
          0x0001: Not in a vacuum
          0x0002: Not enough fuel
          0x0003: Inhomogeneous gravitational field
          0x0004: Too much angular momentum
          0x0005: One or more cell doors are open
          0x0006: Mechanical error
          0xffff: Unknown error - EVACUATE VESSEL IMMEDIATELY
    1: SET_UNIT_TO_SKIP
       Reads the B register, and reads a 64 bit number from memory address B
       in big endian, and sets the number of units to skip to that number.
    2: TRIGGER_DEVICE
       Performs GET_STATUS, and if C is 1, triggers the SCP2000. The status can
       be read as the result of the GET_STATUS call.
    3: SET_SKIP_UNIT
       Reads the B register, and sets the size of the unit to skip to one of:
           0x0000: Milliseconds
           0x0001: Minutes
           0x0002: Days
           0x0003: Years
       
       
A message from Ola:
    Good morning,
   
    Thanks for purchasing this piece of hardware! I hope it will enlighten you
    and give you new hope in life. As this suspension chamber basically works as
    a one way time machine, I suppose I should wish you a pleasant journey, and
    ask of you to enjoy the future. It is yours now. All of it.
   
    - Ola Kristian Carlsson
```
