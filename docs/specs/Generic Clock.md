```
Name: Generic Clock (compatible)
ID: 0x12d0b402
Version: 1

Interrupts do different things depending on contents of the A register:

 A | BEHAVIOR
---+----------------------------------------------------------------------------
 0 | The B register is read, and the clock will tick 60/B times per second.
   | If B is 0, the clock is turned off.
 1 | Store number of ticks elapsed since last call to 0 in C register
 2 | If register B is non-zero, turn on interrupts with message B. If B is zero,
   | disable interrupts
---+----------------------------------------------------------------------------

When interrupts are enabled, the clock will trigger an interrupt whenever it
ticks.
```
