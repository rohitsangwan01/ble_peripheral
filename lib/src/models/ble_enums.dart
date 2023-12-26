enum CharacteristicProperties {
  broadcast,
  read,
  writeWithoutResponse,
  write,
  notify,
  indicate,
  authenticatedSignedWrites,
  extendedProperties
}

enum AttributePermissions {
  readable,
  writeable,
  readEncryptionRequired,
  writeEncryptionRequired
}

enum BondState {
  bonding,
  bonded,
  none;

  static BondState fromInt(int value) {
    switch (value) {
      case 0:
        return BondState.bonding;
      case 1:
        return BondState.bonded;
      case 2:
        return BondState.none;
      default:
        throw ArgumentError.value(value, 'value', 'Invalid value');
    }
  }
}
