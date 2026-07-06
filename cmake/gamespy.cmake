set(GS_OPENSSL FALSE)
set(GAMESPY_SERVER_NAME "server.cnc-online.net")

FetchContent_Declare(
    gamespy
    GIT_REPOSITORY https://github.com/TheAssemblyArmada/GamespySDK.git
    GIT_TAG        07e3d15c500415abc281efb74322ab6d9c857eb8
)

FetchContent_MakeAvailable(gamespy)

# GeneralsX @build FadiLabib 06/07/2026 Android's bionic libc has no pthread_cancel.
# gamespy compiles the Linux thread backend (common/linux/gsthreadlinux.c) on Android, and
# its only user of pthread_cancel is gsiCancelThread() — a best-effort forced cancel at
# shutdown that merely logs a warning if the call fails. Rather than patch the fetched
# upstream sources (not ours to edit), neutralize the call on Android by expanding it to a
# nonzero (error) result: the existing "Failed to cancel thread" path is taken and the
# worker thread is left to exit on its own. Scoped to the gscommon target on Android only,
# so no other platform's gamespy build changes.
if(ANDROID AND TARGET gscommon)
    # Passed as a raw compile option (not target_compile_definitions) because CMake silently
    # drops function-like macros — with parameters — from COMPILE_DEFINITIONS.
    target_compile_options(gscommon PRIVATE "-Dpthread_cancel(thread)=(1)")
endif()
