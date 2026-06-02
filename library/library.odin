package library

import "core:c"

IsAndroid :: ODIN_PLATFORM_SUBTARGET == .Android
IsMobile ::
	ODIN_PLATFORM_SUBTARGET == .Android ||
	ODIN_PLATFORM_SUBTARGET == .iPhone ||
	ODIN_PLATFORM_SUBTARGET == .iPhoneSimulator

when ODIN_ARCH == .amd64 {
	__ArchEnd :: "_amd64"
} else when ODIN_ARCH == .i386 {
	__ArchEnd :: "_i386"
} else when ODIN_ARCH == .arm64 {
	__ArchEnd :: "_arm64"
} else when ODIN_ARCH == .riscv64 {
	__ArchEnd :: "_riscv64"
} else when ODIN_ARCH == .arm32 {
	__ArchEnd :: "_arm32"
} else when ODIN_OS == .JS || ODIN_OS == .WASI {
	__ArchEnd :: "_wasm"
}

when ODIN_OS == .Windows && !IsMobile {
	ArchEnd :: __ArchEnd + ".lib"
	ArchEndSo :: __ArchEnd + ".dll"
} else {
	ArchEnd :: __ArchEnd + ".a"
	ArchEndSo :: __ArchEnd + ".so"
}

when !IsMobile {
	when ODIN_OS == .Windows {
		Libpath :: "/lib/windows"
	} else when ODIN_OS == .Darwin {
		//TODO
	} else {
		Libpath :: "/lib/linux"
	}
} else {
	when IsAndroid {
		Libpath :: "/lib/android"
	}
}
