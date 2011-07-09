Skein for ARMv7 with NEON
=========================

This is an implementation of the Skein_ hash function, as described in
`The Skein Hash Function Family`_, version 1.3.

The implementation is targeted towards the ARM Cortex-A8_ processor, and
uses the NEON_ SIMD instructions to perform 64-bit operations, where
possible in parallel.

There is also a Skein-256 implementation that does not require NEON support.

The code is based on the optimized C version written by Doug Whiting, with the
block functions rewritten in ARM assembly language.


Performance
-----------
For long messages the implementation reaches the following speeds in
cycles per byte when tested on Cortex-A8 processor:

========== ====
Skein-256  20.3
Skein-512  15.4
Skein-1024 20.2
========== ====

Without SIMD:

========== ====
Skein-256  21.7
========== ====


See performance_test.txt for more detailed test output.


Compiling and running the test program
--------------------------------------
The Skein test program can be compiled using GCC as follows::

  gcc *.c skein_block_cortexa8.S -DSKEIN_USE_ASM=256+512+1024

In order for the performance test to have an accurate timer, you will need
to enable user mode access to the ARM performance monitor registers.

One way to do this is to use the kernel module included in the `userperf`
folder.



.. _Skein: http://skein-hash.info
.. _`The Skein Hash Function Family`: http://www.skein-hash.info/sites/default/files/skein1.3.pdf
.. _Cortex-A8: http://www.arm.com/products/processors/cortex-a/cortex-a8.php
.. _NEON: http://www.arm.com/products/processors/technologies/neon.php
