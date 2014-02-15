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

#define IN_BIT_CHANNEL      1
#define IN_BYTE_CHANNEL     2
#define OUT_BIT_CHANNEL     1
#define OUT_BYTE_CHANNEL    2

#define IN_BIT_UART_CTS         (1 << 0)
#define IN_BIT_DDC_BUSY         (1 << 1)
#define IN_BIT_TRANSM_ERROR     (1 << 2)
#define IN_BIT_DATA_VALID       (1 << 3)
#define IN_BIT_HDMI_DETECT      (1 << 4)
#define IN_BYTE_INDEX           0x000000FF
#define IN_BYTE_DATA            0x0000FF00
#define IN_BYTE_POS_INDEX       0
#define IN_BYTE_POS_DATA        1

#define OUT_BIT_UART_RTS        (1 << 0)
#define OUT_BIT_DDC_START       (1 << 1)
#define OUT_BIT_LED0            (1 << 2)
//#define OUT_BIT_LED1            (1 << 3)
#define OUT_BYTE_BLOCK_NUM      0x000000FF
#define OUT_BYTE_POS_BLOCK_NUM  0

void
usleep(unsigned long micros);

void
sleep(unsigned long seconds);

void
gpi1_interrupt(void* instancePtr);

void
uart_error_interrupt(void* instancePtr);

void
assert_callback(char *FilenamePtr, int LineNumber);

XIOModule io;
u32 prev_in_reg1;
u8 edid_table[128];

int
main()
{
    init_platform();
    XAssertSetCallback((XAssertCallback) assert_callback);

    if (io.IsStarted)
        XIOModule_Stop(&io);

    XASSERT_NONVOID(XIOModule_Initialize(&io, XPAR_IOMODULE_0_DEVICE_ID) == XST_SUCCESS);
    XASSERT_NONVOID(XIOModule_SetOptions(&io, XIN_SVC_ALL_ISRS_OPTION) == XST_SUCCESS);

    microblaze_register_handler(XIOModule_DeviceInterruptHandler, XPAR_IOMODULE_0_DEVICE_ID);

    XASSERT_NONVOID(XIOModule_Start(&io) == XST_SUCCESS);

    /* Input GPI1 */
    XASSERT_NONVOID(
            XIOModule_Connect(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR, (XInterruptHandler) gpi1_interrupt, NULL) == XST_SUCCESS);
    XIOModule_Enable(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR);

    /* Uart error */
    XASSERT_NONVOID(
            XIOModule_Connect(&io, XIN_IOMODULE_UART_ERROR_INTERRUPT_INTR, (XInterruptHandler) uart_error_interrupt, NULL) == XST_SUCCESS);
    XIOModule_Enable(&io, XIN_IOMODULE_UART_ERROR_INTERRUPT_INTR);

    // enable reception of UART data
    XIOModule_DiscreteSet(&io, OUT_BIT_CHANNEL, OUT_BIT_UART_RTS);
    // wait until the UART host can receive data
    while (~XIOModule_DiscreteRead(&io, IN_BIT_CHANNEL) & IN_BIT_UART_CTS)
    {
    }

    prev_in_reg1 = XIOModule_DiscreteRead(&io, IN_BIT_CHANNEL) & ~IN_BIT_HDMI_DETECT;

    print("init\r\n");

    microblaze_enable_interrupts();

    while (1)
    {
    }

    cleanup_platform();

    return 0;
}

void
gpi1_interrupt(void* instancePtr)
{
    u32 in_reg1, in_reg2, flanks;
    u8 data, index, i;
    XIOModule_Acknowledge(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR);

    in_reg1 = XIOModule_DiscreteRead(&io, IN_BIT_CHANNEL);
    flanks = in_reg1 ^ prev_in_reg1;
    if (flanks & IN_BIT_HDMI_DETECT && in_reg1 & IN_BIT_HDMI_DETECT)
    {
        // rising edge of 'HDMI detect'
        print("Detected new device, retrieving EDID...");
        XIOModule_DiscreteWrite(&io, 2, (0 << OUT_BYTE_POS_BLOCK_NUM) & OUT_BYTE_BLOCK_NUM);
        XIOModule_DiscreteSet(&io, OUT_BIT_CHANNEL, OUT_BIT_DDC_START);
        XIOModule_DiscreteClear(&io, OUT_BIT_CHANNEL, OUT_BIT_DDC_START);
    }

    if (flanks & IN_BIT_DATA_VALID && in_reg1 & IN_BIT_DATA_VALID)
    {
        // rising edge of 'data valid'
        in_reg2 = XIOModule_DiscreteRead(&io, IN_BYTE_CHANNEL);
        data = (in_reg2 & IN_BYTE_DATA) >> IN_BYTE_POS_DATA;
        index = (in_reg2 & IN_BYTE_INDEX) >> IN_BYTE_POS_INDEX;
        edid_table[index] = data;
    }

    if (flanks & IN_BIT_DDC_BUSY)
    {
        if (in_reg1 & IN_BIT_DDC_BUSY)
        {
            // rising edge of 'busy'
            XIOModule_DiscreteSet(&io, OUT_BIT_CHANNEL, OUT_BIT_LED0);
        }
        else
        {
            // falling edge of 'busy'
            XIOModule_DiscreteClear(&io, OUT_BIT_CHANNEL, OUT_BIT_LED0);

            if (in_reg1 & IN_BIT_TRANSM_ERROR)
            {
                print("There was a transmission error while reading the EDID table!");
            }
            else
            {
                print("Got a complete EDID block:");
                for (i = 0; i < 128; i++)
                {
                    xil_printf("%x\r\n", edid_table[i]);
                }
            }
        }
    }

    prev_in_reg1 = in_reg1;
}

void
uart_error_interrupt(void* instancePtr)
{
    XIOModule_Acknowledge(&io, XIN_IOMODULE_UART_ERROR_INTERRUPT_INTR);
    print("UART error interrupt\r\n");
}

void
assert_callback(char *FilenamePtr, int LineNumber)
{
    xil_printf("Assert failed in file '%s' line %d\r\n", FilenamePtr, LineNumber);
}
