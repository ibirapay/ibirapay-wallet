allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // The Spark SDK plugin pulls androidx.credentials-play-services-auth (passkeys) and with it the proprietary
    // Google Play Services. This wallet does not use passkeys, so keep every gms artifact out of the APK.
    configurations.all {
        exclude(group = "com.google.android.gms")
        exclude(group = "androidx.credentials", module = "credentials-play-services-auth")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
