#!/usr/bin/env python3
# Taken from https://github.com/twam/EDID

import re


class Edid_descriptor:
    SIZE = 18

    def __init__(self, parent, offset):
        self.parent = parent
        self.offset = offset

    def __getitem__(self, key):
        if isinstance(key, int):
            if key >= 0 and key < self.SIZE:
                new_key = key + self.offset
            elif key < 0 and key >= -self.SIZE:
                new_key = key + self.SIZE + self.offset
            else:
                raise Index_error

            return self.parent[new_key]
        elif isinstance(key, slice):
            if key.start is None:
                new_start = self.offset
            elif key.start >= 0:
                new_start = min(key.start, self.SIZE) + self.offset
            elif key.start < 0:
                new_start = max(0, key.start + self.SIZE) + self.offset
            else:
                raise Index_error

            if key.stop is None:
                new_stop = self.offset + self.SIZE
            elif key.stop >= 0:
                new_stop = min(key.stop, self.SIZE) + self.offset
            elif key.stop < 0:
                new_stop = max(0, key.stop + self.SIZE) + self.offset
            else:
                raise Index_error

            return self.parent[slice(new_start, new_stop, key.step)]
        else:
            raise Type_error

    def __setitem__(self, key, value):
        if isinstance(key, int):
            if key >= 0 and key < self.SIZE:
                new_key = key + self.offset
            elif key < 0 and key >= -self.SIZE:
                new_key = key + self.SIZE + self.offset
            else:
                raise Index_error

            self.parent[new_key] = value
        else:
            raise Type_error

    def get_header(self):
        return self[0:2]


class Edid(bytearray):
    HEADER = bytearray.fromhex('00 FF FF FF FF FF FF 00')

    def __init__(self, data=None, version=None):
        if data:
            self[:] = data
            return

        self[:] = bytearray(128)
        self.init_header()

        if version:
            self.set_edid_version(int(version))
            self.set_edid_revision(int((version - int(version)) * 10))

        # set all standard timing information to invalid
        for index in range(0, 8):
            self.set_standard_timing_information(index, None, None, None)

    def calculate_checksum(self):
        val = 0

        for i in self[0:127]:
            val += i

        self[-1] = (256 - (val % 256)) % 256

    def check_checksum(self):
        val = 0
        for i in self[0:128]:
            val += i

        return val % 256 == 0

    # Header information (0-19)

    def check_header(self):
        return self[0:8] == self.HEADER

    def init_header(self):
        self[0:8] = self.HEADER

    def set_manufacturer_iD(self, manufacturer_iD):
        if not isinstance(manufacturer_iD, str):
            return Type_error
        if not re.match('^[A-Z]{3}$', manufacturer_iD):
            return Value_error

        raw = (
            (ord(
                manufacturer_iD[0]) -
                64) << 10) | (
            (ord(
                manufacturer_iD[1]) -
                64) << 5) | (
                    (ord(
                        manufacturer_iD[2]) -
                     64) << 0)

        self[8:10] = (raw.to_bytes(2, byteorder='big'))

    def get_manufacturer_iD(self):
        raw = int.from_bytes(self[8:10], byteorder='big')
        return chr(((raw >> 10) & 0x1F) + 64) + \
            chr(((raw >> 5) & 0x1F) + 64) + chr(((raw >> 0) & 0x1F) + 64)

    def set_manufacturer_product_code(self, manufacturer_product_code):
        if not isinstance(manufacturer_product_code, int):
            raise Type_error
        if not (manufacturer_product_code >=
                0 and manufacturer_product_code <= 0x_fFFF):
            raise Value_error

        self[10:12] = manufacturer_product_code.to_bytes(2, byteorder='little')

    def get_manufacturer_product_code(self):
        return int.from_bytes(self[10:12], byteorder='little')

    def set_serial_number(self, serial_number):
        if not isinstance(serial_number, int):
            raise Type_error
        if not (serial_number >=
                0 and serial_number <= 0x_fFFFFFFF):
            raise Value_error

        self[12:16] = serial_number.to_bytes(4, byteorder='little')

    def get_serial_number(self):
        return int.from_bytes(self[12:16], byteorder='little')

    def set_week_of_manufacture(self, week_of_manufacture):
        if not isinstance(week_of_manufacture, int):
            raise Type_error
        if not (week_of_manufacture >=
                0 and week_of_manufacture <= 0x_fF):
            raise Value_error

        self[16] = week_of_manufacture

    def get_week_of_manufacture(self):
        return self[16]

    def set_year_of_manufacture(self, year_of_manufacture):
        if not isinstance(year_of_manufacture, int):
            raise Type_error
        if not (year_of_manufacture >=
                1990 and year_of_manufacture <= 2245):
            raise Value_error

        self[17] = year_of_manufacture - 1990

    def get_year_of_manufacture(self):
        return 1990 + self[17]

    def set_edid_version(self, edid_version):
        if not isinstance(edid_version, int):
            raise Type_error
        if not (edid_version >=
                0 and edid_version <= 0x_fF):
            raise Value_error

        self[18] = edid_version

    def get_edid_version(self):
        return self[18]

    def set_edid_revision(self, edid_revision):
        if not isinstance(edid_revision, int):
            raise Type_error
        if not (edid_revision >=
                0 and edid_revision <= 0x_fF):
            raise Value_error

        self[19] = edid_revision

    def get_edid_revision(self):
        return self[19]

    def get_version(self):
        return float(self.get_edid_version()) + \
            float(self.get_edid_revision()) / 10.0

    # Basic display parameters (20-24)

    def set_video_input_parameters_bitmap(self, video_input_parameters_bitmap):
        if not isinstance(video_input_parameters_bitmap, int):
            raise Type_error
        if not (video_input_parameters_bitmap >=
                0 and video_input_parameters_bitmap <= 0x_fF):
            raise Value_error

        self[20] = video_input_parameters_bitmap

    def get_video_input_parameters_bitmap(self):
        return self[20]

    def set_maximum_horizontal_image_size(self, maximum_horizontal_image_size):
        if not isinstance(maximum_horizontal_image_size, int):
            raise Type_error
        if not (maximum_horizontal_image_size >=
                0 and maximum_horizontal_image_size <= 0x_fF):
            raise Value_error

        self[21] = maximum_horizontal_image_size

    def get_maximum_horizontal_image_size(self):
        return self[21]

    def set_maximum_vertical_image_size(self, maximum_vertical_image_size):
        if not isinstance(maximum_vertical_image_size, int):
            raise Type_error
        if not (maximum_vertical_image_size >=
                0 and maximum_vertical_image_size <= 0x_fF):
            raise Value_error

        self[22] = maximum_vertical_image_size

    def get_maximum_vertical_image_size(self):
        return self[22] * 100

    def set_display_gamma(self, display_gamma):
        if not isinstance(display_gamma, float):
            raise Type_error
        if not (display_gamma >=
                1.0 and display_gamma <= 3.54):
            raise Value_error

        self[23] = int((display_gamma * 100) - 100)

    def get_display_gamma(self):
        return (float(self[23]) + 100.0) / 100.0

    def set_supported_features_bitmap(self, supported_features_bitmap):
        if not isinstance(supported_features_bitmap, int):
            raise Type_error
        if not (supported_features_bitmap >=
                0 and supported_features_bitmap <= 0x_fF):
            raise Value_error

        self[24] = supported_features_bitmap

    def get_supported_features_bitmap(self):
        return self[24]

    # Chromaticity coordinates (25-34)

    def set_chromaticity_coordinates_red(
            self, X, Y):
        if ((not isinstance(X, float)) or (not isinstance(Y, float))):
            return Type_error

        if ((not (X >= 0 and X <= 1.0)) or (not (Y >= 0 and Y <= 1.0))):
            raise Value_error

        Xint = int(round(X * 1024, 0))
        Yint = int(round(Y * 1024, 0))

        self[25] = (((Xint & 0x03) | (Yint & 0x03)) << 4) | (self[25] & 0x0F)

        self[27] = Xint >> 2
        self[28] = Yint >> 2

    def set_chromaticity_coordinates_green(
            self, X, Y):
        if ((not isinstance(X, float)) or (not isinstance(Y, float))):
            return Type_error

        if ((not (X >= 0 and X <= 1.0)) or (not (Y >= 0 and Y <= 1.0))):
            raise Value_error

        Xint = int(round(X * 1024, 0))
        Yint = int(round(Y * 1024, 0))

        self[25] = (((Xint & 0x03) | (Yint & 0x03)) << 0) | (self[25] & 0x_f0)

        self[29] = Xint >> 2
        self[30] = Yint >> 2

    def set_chromaticity_coordinates_blue(
            self, X, Y):
        if ((not isinstance(X, float)) or (not isinstance(Y, float))):
            return Type_error

        if ((not (X >= 0 and X <= 1.0)) or (not (Y >= 0 and Y <= 1.0))):
            raise Value_error

        Xint = int(round(X * 1024, 0))
        Yint = int(round(Y * 1024, 0))

        self[26] = (((Xint & 0x03) | (Yint & 0x03)) << 4) | (self[25] & 0x0F)

        self[31] = Xint >> 2
        self[32] = Yint >> 2

    def set_chromaticity_coordinates_white(
            self, X, Y):
        if ((not isinstance(X, float)) or (not isinstance(Y, float))):
            return Type_error

        if ((not (X >= 0 and X <= 1.0)) or (not (Y >= 0 and Y <= 1.0))):
            raise Value_error

        Xint = int(round(X * 1024, 0))
        Yint = int(round(Y * 1024, 0))

        self[26] = (((Xint & 0x03) | (Yint & 0x03)) << 0) | (self[25] & 0x_f0)

        self[33] = Xint >> 2
        self[34] = Yint >> 2

    def get_chromaticity_coordinates_red(self):
        X = round(((self[27] << 2) | ((self[25] >> 6) & 0x03)) / 1024.0, 3)
        Y = round(((self[28] << 2) | ((self[25] >> 4) & 0x03)) / 1024.0, 3)

        return X, Y

    def get_chromaticity_coordinates_green(self):
        X = round(((self[29] << 2) | ((self[25] >> 2) & 0x03)) / 1024.0, 3)
        Y = round(((self[30] << 2) | ((self[25] >> 0) & 0x03)) / 1024.0, 3)

        return X, Y

    def get_chromaticity_coordinates_blue(self):
        X = round(((self[31] << 2) | ((self[26] >> 6) & 0x03)) / 1024.0, 3)
        Y = round(((self[32] << 2) | ((self[26] >> 4) & 0x03)) / 1024.0, 3)

        return X, Y

    def get_chromaticity_coordinates_white(self):
        X = round(((self[33] << 2) | ((self[26] >> 2) & 0x03)) / 1024.0, 3)
        Y = round(((self[34] << 2) | ((self[26] >> 0) & 0x03)) / 1024.0, 3)

        return X, Y

    # Established timing bitmap. Supported bitmap for (formerly) very common
    # timing modes (35-37)

    def set_established_timing_bitmap(self, established_timing_bitmap):
        if not isinstance(established_timing_bitmap, int):
            raise Type_error
        if not (established_timing_bitmap >=
                0 and established_timing_bitmap <= 0x_fFFFFF):
            raise Value_error

        self[35:38] = established_timing_bitmap.to_bytes(3, byteorder='big')

    def get_established_timing_bitmap(self):
        return int.from_bytes(self[35:38], byteorder='big')

    # Standard timing information (38-53)

    def set_standard_timing_information(
            self, index, resolution_x, ratio, vertical_frequency):
        if (resolution_x is None) and (ratio is None) and (
                vertical_frequency is None):
            self[38 + 2 * index + 0] = 1
            self[38 + 2 * index + 1] = 1
            return

        if not isinstance(resolution_x, int):
            raise Type_error
        if not isinstance(ratio, float):
            raise Type_error
        if not isinstance(vertical_frequency, int):
            raise Type_error

        if not (resolution_x >= 256 and
                resolution_x <= 2288 and resolution_x % 8 == 0):
            raise Value_error
        if not (vertical_frequency >=
                60 and vertical_frequency <= 123):
            raise Value_error

        self[38 + 2 * index + 0] = (resolution_x >> 3) - 31

        if (ratio == 1.0):
            if (self.get_version() < 1.3):
                self[38 + 2 * index + 1] = 0
            else:
                raise Value_error
        elif (ratio == 16.0 / 10.0):
            if (self.get_version() >= 1.3):
                self[38 + 2 * index + 1] = 0
            else:
                raise Value_error
        elif (ratio == 4.0 / 3.0):
            self[38 + 2 * index + 1] = 1 << 6
        elif (ratio == 5.0 / 4.0):
            self[38 + 2 * index + 1] = 2 << 6
        elif (ratio == 16.0 / 9.0):
            self[38 + 2 * index + 1] = 3 << 6

        self[
            38 +
            2 *
            index +
            1] = self[
            38 +
            2 *
            index +
            1] | (
            vertical_frequency -
            60)

    def get_standard_timing_information(self, index):
        # check for invalid entry
        if (self[38 + 2 * index + 0] == 1) and (self[38 + 2 * index + 1] == 1):
            return None, None, None

        resolution_x = 8 * (31 + self[38 + 2 * index + 0])
        ratio_raw = self[38 + 2 * index + 1] >> 6
        if (ratio_raw == 0) and (self.get_version() < 1.3):
            ratio = 1.0
        elif (ratio_raw == 0):
            ratio = 16.0 / 10.0
        elif (ratio_raw == 1):
            ratio = 4.0 / 3.0
        elif (ratio_raw == 2):
            ratio = 5.0 / 4.0
        elif (ratio_raw == 3):
            ratio = 16.0 / 9.0
        else:
            ratio = None
        vertical_frequency = 60 + (self[38 + 2 * index + 1] & 0x3F)

        return resolution_x, ratio, vertical_frequency

    def set_number_of_extensions(self, number_of_extensions):
        if not isinstance(number_of_extensions, int):
            raise Type_error

        if not (number_of_extensions >= 0 and
                number_of_extensions <= 0x_fF):
            raise Value_error

        self[126] = number_of_extensions

    def get_number_of_extensions(self):
        return self[126]

    def write_to_file(self, filename):
        with open(filename, 'wb') as f:
            f.write(self)


def main():
    print(round(0.5, 0))

    edid = Edid(version=1.3)

    edid.set_header()

    edid.set_manufacturer_iD('ABC')
    print(edid.get_manufacturer_iD())

    edid.set_manufacturer_product_code(12345)
    print(edid.get_manufacturer_product_code())

    edid.set_serial_number(12345678)
    print(edid.get_serial_number())

    edid.set_week_of_manufacture(120)
    print(edid.get_week_of_manufacture())

    edid.set_year_of_manufacture(2016)
    print(edid.get_year_of_manufacture())

    edid.set_display_gamma(2.2)

    edid.set_standard_timing_information(0, 640, 4.0 / 3.0, 60)

    edid.set_video_input_parameters_bitmap(0x80)

    edid.calculate_checksum()
    edid.write_to_file('edid.dat')

if __name__ == "__main__":
    main()
