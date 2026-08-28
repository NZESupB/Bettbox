const _useDevIdentity = bool.fromEnvironment('APP_DEV');

class AppIdentity {
  static const isDev = _useDevIdentity;

  static const productName = 'KitonyBox';
  static const desktopIdentityName = 'KitonyBox';
  static const devSuffix = 'Dev';
  static const packageId = 'com.appshub.kitonybox';

  static const compactName = isDev
      ? '$desktopIdentityName$devSuffix'
      : desktopIdentityName;
  static const displayName = isDev ? '$productName Dev' : productName;
  static const mainExecutableName = desktopIdentityName;
  static const coreExecutableName = '${compactName}Core';
  static const dataDirName = compactName;
  static const tunDeviceName = compactName;
}

class WindowsHelperIdentity {
  static const serviceName = '${AppIdentity.compactName}HelperService';
  static const pipeName = '\\\\.\\pipe\\${AppIdentity.compactName}.Helper';
}
