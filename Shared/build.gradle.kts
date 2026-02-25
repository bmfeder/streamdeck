plugins {
    kotlin("multiplatform") version "2.1.10"
}

repositories {
    mavenCentral()
    google()
}

kotlin {
    // iOS targets — generates an XCFramework that Xcode can consume
    listOf(
        iosArm64(),       // physical Apple TV / iPhone
        iosSimulatorArm64() // Apple Silicon simulator
    ).forEach { target ->
        target.binaries.framework {
            baseName = "Shared"
            isStatic = true
        }
    }

    // Future: Android target will be added here
    // androidTarget()

    sourceSets {
        commonMain.dependencies {
            // Shared dependencies go here (Ktor, kotlinx.serialization, etc.)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
        iosMain.dependencies {
            // iOS-specific dependencies
        }
    }
}
