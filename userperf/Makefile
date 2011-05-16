obj-m := userperf.o
#KSDIR=/lib/modules/$(shell uname -r)/build 
KSDIR=/path/to/kernel

all:
	make -C $(KSDIR) M=$(PWD) modules

clean:
	make -C $(KSDIR) M=$(PWD) clean
