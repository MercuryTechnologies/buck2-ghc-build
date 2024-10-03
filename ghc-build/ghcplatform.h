#if !defined(__GHCPLATFORM_H__)
#define __GHCPLATFORM_H__

#ifdef darwin_HOST_OS
#define BuildPlatform_TYPE  aarch64_apple_darwin
#define HostPlatform_TYPE   aarch64_apple_darwin

#define aarch64_apple_darwin_BUILD  1
#define aarch64_apple_darwin_HOST  1

#define aarch64_BUILD_ARCH  1
#define aarch64_HOST_ARCH  1
#define BUILD_ARCH  "aarch64"
#define HOST_ARCH  "aarch64"

#define darwin_BUILD_OS  1
#define darwin_HOST_OS  1
#define BUILD_OS  "darwin"
#define HOST_OS  "darwin"

#define apple_BUILD_VENDOR  1
#define apple_HOST_VENDOR  1
#define BUILD_VENDOR  "apple"
#define HOST_VENDOR  "apple"

#else

#define BuildPlatform_TYPE  x86_64_unknown_linux
#define HostPlatform_TYPE   x86_64_unknown_linux

#define x86_64_unknown_linux_BUILD  1
#define x86_64_unknown_linux_HOST  1

#define x86_64_BUILD_ARCH  1
#define x86_64_HOST_ARCH  1
#define BUILD_ARCH  "x86_64"
#define HOST_ARCH  "x86_64"

#define linux_BUILD_OS  1
#define linux_HOST_OS  1
#define BUILD_OS  "linux"
#define HOST_OS  "linux"

#define unknown_BUILD_VENDOR  1
#define unknown_HOST_VENDOR  1
#define BUILD_VENDOR  "unknown"
#define HOST_VENDOR  "unknown"

#endif

#endif /* __GHCPLATFORM_H__ */
