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
