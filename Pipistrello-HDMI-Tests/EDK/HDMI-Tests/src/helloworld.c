/*
 * Copyright (c) 2009-2012 Xilinx, Inc.  All rights reserved.
 *
 * Xilinx, Inc.
 * XILINX IS PROVIDING THIS DESIGN, CODE, OR INFORMATION "AS IS" AS A
 * COURTESY TO YOU.  BY PROVIDING THIS DESIGN, CODE, OR INFORMATION AS
 * ONE POSSIBLE   IMPLEMENTATION OF THIS FEATURE, APPLICATION OR
 * STANDARD, XILINX IS MAKING NO REPRESENTATION THAT THIS IMPLEMENTATION
 * IS FREE FROM ANY CLAIMS OF INFRINGEMENT, AND YOU ARE RESPONSIBLE
 * FOR OBTAINING ANY RIGHTS YOU MAY REQUIRE FOR YOUR IMPLEMENTATION.
 * XILINX EXPRESSLY DISCLAIMS ANY WARRANTY WHATSOEVER WITH RESPECT TO
 * THE ADEQUACY OF THE IMPLEMENTATION, INCLUDING BUT NOT LIMITED TO
 * ANY WARRANTIES OR REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE
 * FROM CLAIMS OF INFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE.
 *
 */

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xiomodule.h"
#include "xiomodule_l.h"

void
usleep(unsigned long micros);

void
gpi1_interrupt(void* instancePtr);

void
fit_interrupt(void* instancePtr);

void
assert_callback(char *FilenamePtr, int LineNumber);

XIOModule io;
unsigned long timeout;

int
main()
{
    timeout = 0;

    init_platform();
    XAssertSetCallback((XAssertCallback) assert_callback);

    if (io.IsStarted)
        XIOModule_Stop(&io);

    XASSERT_NONVOID(XIOModule_Initialize(&io, XPAR_IOMODULE_0_DEVICE_ID) == XST_SUCCESS);

    microblaze_register_handler(XIOModule_DeviceInterruptHandler, XPAR_IOMODULE_0_DEVICE_ID);

    XASSERT_NONVOID(XIOModule_Start(&io) == XST_SUCCESS);

    /* Timer FIT1 */
    XASSERT_NONVOID(
            XIOModule_Connect(&io, XIN_IOMODULE_FIT_1_INTERRUPT_INTR, (XInterruptHandler) fit_interrupt, NULL) == XST_SUCCESS);

    /* Input GPI1 */
    XASSERT_NONVOID(
            XIOModule_Connect(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR, (XInterruptHandler) gpi1_interrupt, NULL) == XST_SUCCESS);

    XIOModule_Enable(&io, XIN_IOMODULE_FIT_1_INTERRUPT_INTR);
    XIOModule_Enable(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR);

    print("init\r\n");

    microblaze_enable_interrupts();

    XIOModule_DiscreteWrite(&io, 1, 2);
    XIOModule_DiscreteWrite(&io, 1, 0);

    while (1)
    {
        /*
         XIOModule_DiscreteWrite(&io, 1, 4);
         usleep(500000);
         XIOModule_DiscreteWrite(&io, 1, 0);
         usleep(500000);
         */
    }

    cleanup_platform();

    return 0;
}

void
usleep(unsigned long micros)
{
    timeout = micros;
    while (timeout)
    {
    }
}

void
gpi1_interrupt(void* instancePtr)
{
    XIOModule_Acknowledge(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR);
    print("GPI1 interrupt\r\n");
}

void
fit_interrupt(void* instancePtr)
{
    XIOModule_Acknowledge(&io, XIN_IOMODULE_FIT_1_INTERRUPT_INTR);
    if (timeout)
        timeout--;
}

void
assert_callback(char *FilenamePtr, int LineNumber)
{
    xil_printf("Assert failed in file '%s' line %d\r\n", FilenamePtr, LineNumber);
}
