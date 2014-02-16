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
#define IN_BIT_HDMI_DETECT      (1 << 3)
#define IN_BYTE_DATA            0x000000FF
#define IN_BYTE_POS_DATA        0

#define OUT_BIT_UART_RTS        (1 << 0)
#define OUT_BIT_DDC_START       (1 << 1)
#define OUT_BIT_LED0            (1 << 2)
//#define OUT_BIT_LED1            (1 << 3)
#define OUT_BYTE_BLOCK_NUM      0x000000FF
#define OUT_BYTE_INDEX          0x0000FF00
#define OUT_BYTE_POS_BLOCK_NUM  0
#define OUT_BYTE_POS_INDEX      8

#define MIN_HDMI_CONNECT_CYCLES 10000

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

void
eval_gpi(void);

XIOModule io;
static u32 gpi_interrupted, uart_error_interrupted;
static u32 in_reg1;
u32 prev_in_reg1;
u8 edid_table[128];
u8 newly_connected;
u32 conn_timeout;

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

    in_reg1 = XIOModule_DiscreteRead(&io, IN_BIT_CHANNEL);
    prev_in_reg1 = in_reg1 & ~IN_BIT_HDMI_DETECT;
    print("init\r\n");
    gpi_interrupted = FALSE;
    uart_error_interrupted = FALSE;
    conn_timeout = MIN_HDMI_CONNECT_CYCLES;
    newly_connected = FALSE;

    eval_gpi();

    while (1)
    {
        microblaze_disable_interrupts();
        if (gpi_interrupted)
        {
            gpi_interrupted = FALSE;
            eval_gpi();
        }

        if (uart_error_interrupted)
        {
            uart_error_interrupted = FALSE;
            print("UART error interrupt\r\n");
        }

        if (newly_connected)
        {
            if (!--conn_timeout)
            {
                newly_connected = FALSE;

                // Display was connected for MIN_HDMI_CONNECT_CYCLES cycles
                print("Detected new device, retrieving EDID...\r\n");

                // start DDC master to retrieve the EDID table
                XIOModule_DiscreteWrite(&io, OUT_BYTE_CHANNEL,
                        (0 << OUT_BYTE_POS_BLOCK_NUM) & OUT_BYTE_BLOCK_NUM);
                XIOModule_DiscreteSet(&io, OUT_BIT_CHANNEL, OUT_BIT_DDC_START);
                XIOModule_DiscreteClear(&io, OUT_BIT_CHANNEL, OUT_BIT_DDC_START);
            }
        }
        microblaze_enable_interrupts();
    }

    cleanup_platform();

    return 0;
}

void
eval_gpi(void)
{
    u32 flanks;
    u8 data, index;

    flanks = in_reg1 ^ prev_in_reg1;

    if (flanks & IN_BIT_HDMI_DETECT && in_reg1 & IN_BIT_HDMI_DETECT)
    {
        // rising edge of 'HDMI detect'
        conn_timeout = MIN_HDMI_CONNECT_CYCLES;
        newly_connected = TRUE;
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
                print("There was a transmission error while reading the EDID table!\r\n");
            }
            else
            {
                print("Got a complete EDID block:");
                for (index = 0; index < 128; index++)
                {
                    XIOModule_DiscreteWrite(&io, OUT_BYTE_CHANNEL,
                            (index << OUT_BYTE_POS_INDEX) & OUT_BYTE_INDEX);
                    data = (XIOModule_DiscreteRead(&io, IN_BYTE_CHANNEL) & IN_BYTE_DATA)
                            >> IN_BYTE_POS_DATA;

                    // copy the EDID table from the fast external EDID RAM
                    edid_table[index] = data;

                    xil_printf(" 0x%x", data);
                }
                print("\r\n");
            }
        }
    }

    prev_in_reg1 = in_reg1;
}

void
gpi1_interrupt(void* instancePtr)
{
    in_reg1 = XIOModule_DiscreteRead(&io, IN_BIT_CHANNEL);
    xil_printf("gpi int: 0x%x 0x%x\r\n", in_reg1, XIOModule_DiscreteRead(&io, IN_BYTE_CHANNEL));
    XIOModule_Acknowledge(&io, XIN_IOMODULE_GPI_1_INTERRUPT_INTR);
    gpi_interrupted = TRUE;
}

void
uart_error_interrupt(void* instancePtr)
{
    XIOModule_Acknowledge(&io, XIN_IOMODULE_UART_ERROR_INTERRUPT_INTR);
    uart_error_interrupted = TRUE;
}

void
assert_callback(char *FilenamePtr, int LineNumber)
{
    xil_printf("Assert failed in file '%s' line %d\r\n", FilenamePtr, LineNumber);
}
