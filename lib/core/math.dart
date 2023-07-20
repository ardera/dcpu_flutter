bool is16bit(int value) {
  return 0 <= value && value <= 0xFFFF;
}

void check16bit(int value) {
  assert(is16bit(value));
}

int add16bit(int lhs, int rhs) {
  return (lhs + rhs) & 0xFFFF;
}

bool add16bitOverflows(int lhs, int rhs) {
  return (lhs + rhs) > 0xFFFF;
}

int sub16bit(int lhs, int rhs) {
  return (lhs - rhs) & 0xFFFF;
}

bool sub16bitUnderflows(int lhs, int rhs) {
  return lhs - rhs < 0;
}

int to16bit(int value) {
  return value & 0xFFFF;
}

String hexstring(int value) {
  return '0x${value.toRadixString(16).padLeft(4, '0')}';
}

int from16bitsigned(int value) {
  if (value & 0x8000 != 0) {
    return value - 0x10000;
  } else {
    return value;
  }
}

int to16bitsigned(int value) {
  assert(-0x8000 <= value && value < 0x7fff);

  if (value < 0) {
    return value + 0x10000;
  } else {
    return value;
  }
}
