#include <linux/init.h>
#include <linux/module.h>

MODULE_LICENSE("Dual MIT/GPL");

/*
 * Silly little hack module that enables user access to the ARM performance
 * registers by writing to the USEREN register.
 */


static int userperf_init(void)
{
	/* Disable interrupts on overflow for the performance counters */
	asm volatile ("mcr p15, 0, %0, c9, c14, 2" :: "r"(0x8000000f));

	/* Enable user access to the performance counters */
	asm volatile ("mcr p15, 0, %0, c9, c14, 0" :: "r"(1));

	printk(KERN_INFO "User access to performance counter enabled\n");
	return 0;
}


static void userperf_exit(void)
{
	/* Disable user access to the performance counters */
	asm volatile ("mcr p15, 0, %0, c9, c14, 0" :: "r"(0));

	printk(KERN_INFO "User access to performance counter disabled\n");
}


module_init(userperf_init);
module_exit(userperf_exit);
