#!/usr/bin/env python3

HOR_LED_COUNT         =  16
HOR_LED_SCALED_WIDTH  =  96 # 720p: 60 pixel
HOR_LED_SCALED_HEIGHT = 226 # 720p: 80 pixel
HOR_LED_SCALED_STEP   = 128 # 720p: 80 pixel
HOR_LED_SCALED_PAD    =  15 # 720p:  5 pixel
HOR_LED_SCALED_OFFS   =  16 # 720p: 10 pixel
VER_LED_COUNT         =   9
VER_LED_SCALED_WIDTH  = 128 # 720p: 80 pixel
VER_LED_SCALED_HEIGHT = 169 # 720p: 60 pixel
VER_LED_SCALED_STEP   = 226 # 720p: 80 pixel
VER_LED_SCALED_PAD    =   8 # 720p:  5 pixel
VER_LED_SCALED_OFFS   =  29 # 720p: 10 pixel
START_LED_NUM         =   0
FRAME_DELAY           =   0
RGB_MODE              =   0
GAMMA_CORRECTION      = 2.0
MIN_RED               =   0
MAX_RED               = 255
MIN_GREEN             =   0
MAX_GREEN             = 255
MIN_BLUE              =   0
MAX_BLUE              = 255

def gammaCorrect(val, corr):
    return int(255 * pow(val / 255, corr))

def calcGammaTable(corr):
    return list(map(gammaCorrect, range(256), [corr] * 256))

def calcCorrectionTable(corr, minVal, maxVal):
    return list(map(lambda val: max(min(val, maxVal), minVal), calcGammaTable(corr)))

values = [
    HOR_LED_COUNT,
    HOR_LED_SCALED_WIDTH,
    HOR_LED_SCALED_HEIGHT,
    HOR_LED_SCALED_STEP,
    HOR_LED_SCALED_PAD,
    HOR_LED_SCALED_OFFS,
    VER_LED_COUNT,
    VER_LED_SCALED_WIDTH,
    VER_LED_SCALED_HEIGHT,
    VER_LED_SCALED_STEP,
    VER_LED_SCALED_PAD,
    VER_LED_SCALED_OFFS,
    START_LED_NUM,
    FRAME_DELAY,
    RGB_MODE
    ]

values += calcCorrectionTable(GAMMA_CORRECTION, MIN_RED, MAX_RED)
values += calcCorrectionTable(GAMMA_CORRECTION, MIN_GREEN, MAX_GREEN)
values += calcCorrectionTable(GAMMA_CORRECTION, MIN_BLUE, MAX_BLUE)

values += [0] * (256-15)

f = open('settings.bin', 'wb')
f.write(bytes(values))
f.close()