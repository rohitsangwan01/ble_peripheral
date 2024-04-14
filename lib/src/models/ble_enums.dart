// Enums as mapped with index to native side, do not change order
enum CharacteristicProperties {
  broadcast,
  read,
  writeWithoutResponse,
  write,
  notify,
  indicate,
  authenticatedSignedWrites,
  extendedProperties,
  notifyEncryptionRequired,
  indicateEncryptionRequired
}

/// Permissions required to access a characteristic
enum AttributePermissions {
  readable,
  writeable,
  readEncryptionRequired,
  writeEncryptionRequired
}
