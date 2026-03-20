import java.util.Properties
import java.io.FileInputStream
import java.security.Security

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val useYubiKey = System.getenv("YUBIKEY_SIGN") == "1"

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (!useYubiKey && keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Register YubiKey PKCS#11 provider if requested
if (useYubiKey) {
    val pkcs11Config = rootProject.file("yubikey-pkcs11.cfg").absolutePath
    val baseProvider = Security.getProvider("SunPKCS11")
        ?: throw GradleException("SunPKCS11 provider not available")
    val configured = baseProvider.configure(pkcs11Config)
    Security.addProvider(configured)
}

android {
    namespace = "com.vaultapprover.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.vaultapprover.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (useYubiKey) {
                storeType = "PKCS11"
                storeFile = rootProject.file("yubikey-pkcs11.cfg")
                storePassword = System.getenv("YUBIKEY_PIN")
                keyAlias = "X.509 Certificate for Digital Signature"
                keyPassword = System.getenv("YUBIKEY_PIN")
            } else {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (useYubiKey || keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
