## Notes
- Although there is a specification for a keyboard device, Notch's alpha
  releases of 0x10c which included a functional DCPU-16 system did not follow
  this.  
  Instead the keyboard is interfaced through a 16 letter ring buffer mapped at
  0x9000 (non configurable). An address is 0 before a key is pressed, and should
  be written as 0 again after being read so it can be checked later.
  Most emulators follow this functionality.
  - quote: https://github.com/lucaspiller/dcpu-specifications#community-adopted-specifications

## Specification
```
Name: Generic Keyboard (compatible)
ID: 0x30cf7406
Version: 1

Interrupts do different things depending on contents of the A register:

 A | BEHAVIOR
---+----------------------------------------------------------------------------
 0 | Clear keyboard buffer
 1 | Store next key typed in C register, or 0 if the buffer is empty
 2 | Set C register to 1 if the key specified by the B register is pressed, or
   | 0 if it's not pressed
 3 | If register B is non-zero, turn on interrupts with message B. If B is zero,
   | disable interrupts
---+----------------------------------------------------------------------------

When interrupts are enabled, the keyboard will trigger an interrupt when one or
more keys have been pressed, released, or typed.

Key numbers are:
  0x10: Backspace
  0x11: Return
  0x12: Insert
  0x13: Delete
  0x20-0x7f: ASCII characters
  0x80: Arrow up
  0x81: Arrow down
  0x82: Arrow left
  0x83: Arrow right
  0x90: Shift
  0x91: Control
```