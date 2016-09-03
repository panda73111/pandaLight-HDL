#!/usr/bin/env python3

HOR_LED_COUNT         =  16
HOR_LED_SCALED_WIDTH  =  60 / 1280
HOR_LED_SCALED_HEIGHT =  80 / 720
HOR_LED_SCALED_STEP   =  80 / 1280
HOR_LED_SCALED_PAD    =   5 / 720
HOR_LED_SCALED_OFFS   =  10 / 1280
VER_LED_COUNT         =   9
VER_LED_SCALED_WIDTH  =  80 / 1280
VER_LED_SCALED_HEIGHT =  60 / 720
VER_LED_SCALED_STEP   =  80 / 720
VER_LED_SCALED_PAD    =   5 / 1280
VER_LED_SCALED_OFFS   =  10 / 720
START_LED_NUM         =   0
FRAME_DELAY           =   0
RGB_MODE              =   0 # standard RGB
LED_CONTROL_MODE      =   0 # WS2801 chips
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

# save the gamma correction value as 4 Bit + 12 Bit fixed point value
gamma_cor_int   = int(GAMMA_CORRECTION)
gamma_cor_frac  = int((GAMMA_CORRECTION % 1) * 2 ** 12); # 12 Bit fraction

def fractionToShort(fraction):
    i = int(fraction * (2 ** 16 - 1))
    return [i >> 8 & 0xFF, i & 0xFF]

values = [
    HOR_LED_COUNT,
    *fractionToShort(HOR_LED_SCALED_WIDTH),
    *fractionToShort(HOR_LED_SCALED_HEIGHT),
    *fractionToShort(HOR_LED_SCALED_STEP),
    *fractionToShort(HOR_LED_SCALED_PAD),
    *fractionToShort(HOR_LED_SCALED_OFFS),
    VER_LED_COUNT,
    *fractionToShort(VER_LED_SCALED_WIDTH),
    *fractionToShort(VER_LED_SCALED_HEIGHT),
    *fractionToShort(VER_LED_SCALED_STEP),
    *fractionToShort(VER_LED_SCALED_PAD),
    *fractionToShort(VER_LED_SCALED_OFFS),
    START_LED_NUM,
    FRAME_DELAY,
    RGB_MODE,
    LED_CONTROL_MODE,
    (gamma_cor_int << 4) | (gamma_cor_frac >> 8),
    gamma_cor_frac & 0xFF,
    MIN_RED,
    MAX_RED,
    MIN_GREEN,
    MAX_GREEN,
    MIN_BLUE,
    MAX_BLUE
    ]

values += [0] * (256-len(values))

values += calcCorrectionTable(GAMMA_CORRECTION, MIN_RED, MAX_RED)
values += calcCorrectionTable(GAMMA_CORRECTION, MIN_GREEN, MAX_GREEN)
values += calcCorrectionTable(GAMMA_CORRECTION, MIN_BLUE, MAX_BLUE)

f = open('settings.bin', 'wb')
f.write(bytes(values))
f.close()

f = open('settings.hex', 'w')
f.write(''.join('{:02X}'.format(value) for value in values))
f.close()
