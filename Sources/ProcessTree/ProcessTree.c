#include "ProcessTree.h"

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wchar.h>
#include <stdlib.h>
#include <string.h>

static volatile LONG process_tree_control_signal = 0;

static BOOL WINAPI process_tree_console_handler(DWORD control_type) {
    if (control_type == CTRL_C_EVENT || control_type == CTRL_BREAK_EVENT) {
        InterlockedExchange(&process_tree_control_signal, 1);
        return TRUE;
    }
    return FALSE;
}

void process_tree_request_shutdown(void) {
    InterlockedExchange(&process_tree_control_signal, 1);
}

static wchar_t *process_tree_utf8_to_wide(const char *value) {
    int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
    if (length == 0) {
        return NULL;
    }
    wchar_t *result = (wchar_t *)calloc((size_t)length, sizeof(wchar_t));
    if (result == NULL) {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return NULL;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, length) == 0) {
        DWORD error = GetLastError();
        free(result);
        SetLastError(error);
        return NULL;
    }
    return result;
}

static size_t process_tree_quoted_length(const wchar_t *value) {
    size_t length = 2;
    size_t backslashes = 0;
    for (const wchar_t *cursor = value; *cursor != L'\0'; cursor++) {
        if (*cursor == L'\\') {
            backslashes++;
        } else if (*cursor == L'"') {
            length += backslashes * 2 + 2;
            backslashes = 0;
        } else {
            length += backslashes + 1;
            backslashes = 0;
        }
    }
    return length + backslashes * 2;
}

static wchar_t *process_tree_append_quoted(wchar_t *output, const wchar_t *value) {
    int needs_quotes = value[0] == L'\0';
    for (const wchar_t *cursor = value; *cursor != L'\0'; cursor++) {
        if (*cursor == L' ' || *cursor == L'\t' || *cursor == L'"') {
            needs_quotes = 1;
            break;
        }
    }
    if (!needs_quotes) {
        size_t length = wcslen(value);
        memcpy(output, value, length * sizeof(wchar_t));
        return output + length;
    }

    *output++ = L'"';
    size_t backslashes = 0;
    for (const wchar_t *cursor = value; ; cursor++) {
        if (*cursor == L'\\') {
            backslashes++;
        } else if (*cursor == L'"') {
            for (size_t index = 0; index < backslashes * 2 + 1; index++) {
                *output++ = L'\\';
            }
            *output++ = L'"';
            backslashes = 0;
        } else if (*cursor == L'\0') {
            for (size_t index = 0; index < backslashes * 2; index++) {
                *output++ = L'\\';
            }
            *output++ = L'"';
            return output;
        } else {
            for (size_t index = 0; index < backslashes; index++) {
                *output++ = L'\\';
            }
            *output++ = *cursor;
            backslashes = 0;
        }
    }
}

static wchar_t *process_tree_make_command_line(
    const wchar_t *executable,
    const char *const arguments[]
) {
    wchar_t **wide_arguments = NULL;
    size_t argument_count = 0;
    if (arguments != NULL) {
        while (arguments[argument_count] != NULL) {
            argument_count++;
        }
    }
    wide_arguments = (wchar_t **)calloc(argument_count + 1, sizeof(wchar_t *));
    if (wide_arguments == NULL) {
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return NULL;
    }
    size_t capacity = process_tree_quoted_length(executable) + argument_count + 1;
    for (size_t index = 0; index < argument_count; index++) {
        wide_arguments[index] = process_tree_utf8_to_wide(arguments[index]);
        if (wide_arguments[index] == NULL) {
            DWORD error = GetLastError();
            for (size_t cleanup = 0; cleanup < index; cleanup++) {
                free(wide_arguments[cleanup]);
            }
            free(wide_arguments);
            SetLastError(error);
            return NULL;
        }
        capacity += process_tree_quoted_length(wide_arguments[index]) + 1;
    }

    wchar_t *command_line = (wchar_t *)calloc(capacity, sizeof(wchar_t));
    if (command_line == NULL) {
        for (size_t index = 0; index < argument_count; index++) {
            free(wide_arguments[index]);
        }
        free(wide_arguments);
        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return NULL;
    }
    wchar_t *cursor = process_tree_append_quoted(command_line, executable);
    for (size_t index = 0; index < argument_count; index++) {
        *cursor++ = L' ';
        cursor = process_tree_append_quoted(cursor, wide_arguments[index]);
        free(wide_arguments[index]);
    }
    free(wide_arguments);
    return command_line;
}

int process_tree_run(
    const char *executable,
    const char *const arguments[],
    uint32_t grace_period_milliseconds,
    int32_t *exit_status
) {
    if (executable == NULL || exit_status == NULL) {
        return ERROR_INVALID_PARAMETER;
    }
    wchar_t *wide_executable = process_tree_utf8_to_wide(executable);
    if (wide_executable == NULL) {
        return (int)GetLastError();
    }
    wchar_t *command_line = process_tree_make_command_line(wide_executable, arguments);
    if (command_line == NULL) {
        DWORD error = GetLastError();
        free(wide_executable);
        return (int)error;
    }

    HANDLE job = CreateJobObjectW(NULL, NULL);
    if (job == NULL) {
        DWORD error = GetLastError();
        free(command_line);
        free(wide_executable);
        return (int)error;
    }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION job_limits;
    ZeroMemory(&job_limits, sizeof(job_limits));
    job_limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &job_limits,
            sizeof(job_limits)
        )) {
        DWORD error = GetLastError();
        CloseHandle(job);
        free(command_line);
        free(wide_executable);
        return (int)error;
    }

    InterlockedExchange(&process_tree_control_signal, 0);
    if (!SetConsoleCtrlHandler(process_tree_console_handler, TRUE)) {
        DWORD error = GetLastError();
        CloseHandle(job);
        free(command_line);
        free(wide_executable);
        return (int)error;
    }
    STARTUPINFOW startup;
    ZeroMemory(&startup, sizeof(startup));
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process;
    ZeroMemory(&process, sizeof(process));
    BOOL created = CreateProcessW(
        wide_executable,
        command_line,
        NULL,
        NULL,
        FALSE,
        CREATE_SUSPENDED,
        NULL,
        NULL,
        &startup,
        &process
    );
    DWORD error = created ? ERROR_SUCCESS : GetLastError();
    free(command_line);
    free(wide_executable);
    if (!created) {
        SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
        CloseHandle(job);
        return (int)error;
    }
    if (!AssignProcessToJobObject(job, process.hProcess)) {
        error = GetLastError();
        TerminateProcess(process.hProcess, error);
        WaitForSingleObject(process.hProcess, INFINITE);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
        CloseHandle(job);
        return (int)error;
    }
    if (ResumeThread(process.hThread) == (DWORD)-1) {
        error = GetLastError();
        TerminateJobObject(job, error);
        WaitForSingleObject(process.hProcess, INFINITE);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
        CloseHandle(job);
        return (int)error;
    }
    CloseHandle(process.hThread);

    int interrupted = 0;
    ULONGLONG shutdown_started = 0;
    for (;;) {
        DWORD wait_result = WaitForSingleObject(process.hProcess, 25);
        if (wait_result == WAIT_FAILED) {
            error = GetLastError();
            TerminateJobObject(job, error);
            WaitForSingleObject(process.hProcess, INFINITE);
            CloseHandle(process.hProcess);
            SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
            CloseHandle(job);
            return (int)error;
        }
        if (!interrupted && InterlockedCompareExchange(&process_tree_control_signal, 0, 0) != 0) {
            interrupted = 1;
            shutdown_started = GetTickCount64();
        }
        if (interrupted) {
            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
            if (!QueryInformationJobObject(
                    job,
                    JobObjectBasicAccountingInformation,
                    &accounting,
                    sizeof(accounting),
                    NULL
                )) {
                error = GetLastError();
                TerminateJobObject(job, error);
                WaitForSingleObject(process.hProcess, INFINITE);
                CloseHandle(process.hProcess);
                SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
                CloseHandle(job);
                return (int)error;
            }
            if (accounting.ActiveProcesses == 0) {
                break;
            }
            if (GetTickCount64() - shutdown_started >= grace_period_milliseconds) {
                TerminateJobObject(job, ERROR_CANCELLED);
                WaitForSingleObject(process.hProcess, INFINITE);
                break;
            }
        } else if (wait_result == WAIT_OBJECT_0) {
            break;
        }
    }

    DWORD child_exit_status = 0;
    if (!GetExitCodeProcess(process.hProcess, &child_exit_status)) {
        error = GetLastError();
        CloseHandle(process.hProcess);
        SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
        CloseHandle(job);
        return (int)error;
    }
    *exit_status = (int32_t)child_exit_status;
    CloseHandle(process.hProcess);
    SetConsoleCtrlHandler(process_tree_console_handler, FALSE);
    CloseHandle(job);
    return 0;
}

#else

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

static volatile sig_atomic_t process_tree_received_signal = 0;
static pthread_mutex_t process_tree_mutex = PTHREAD_MUTEX_INITIALIZER;

static void process_tree_signal_handler(int signal_number) {
    process_tree_received_signal = signal_number;
}

static int process_tree_group_exists(pid_t process_group) {
    if (kill(-process_group, 0) == 0) {
        return 1;
    }
    return errno != ESRCH;
}

static void process_tree_pause(void) {
    struct timespec delay = {0, 10 * 1000 * 1000};
    while (nanosleep(&delay, &delay) == -1 && errno == EINTR) {
    }
}

static int process_tree_reap(pid_t child, int *status, int *reaped) {
    if (*reaped) {
        return 0;
    }
    pid_t result;
    do {
        result = waitpid(child, status, WNOHANG);
    } while (result == -1 && errno == EINTR);
    if (result == child) {
        *reaped = 1;
        return 0;
    }
    return result == 0 ? 0 : errno;
}

int process_tree_run(
    const char *executable,
    const char *const arguments[],
    uint32_t grace_period_milliseconds,
    int32_t *exit_status
) {
    if (executable == NULL || exit_status == NULL) {
        return EINVAL;
    }

    int lock_error = pthread_mutex_lock(&process_tree_mutex);
    if (lock_error != 0) {
        return lock_error;
    }

    struct sigaction action;
    struct sigaction old_interrupt;
    struct sigaction old_terminate;
    action.sa_handler = process_tree_signal_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    process_tree_received_signal = 0;
    if (sigaction(SIGINT, &action, &old_interrupt) == -1) {
        int error = errno;
        pthread_mutex_unlock(&process_tree_mutex);
        return error;
    }
    if (sigaction(SIGTERM, &action, &old_terminate) == -1) {
        int error = errno;
        sigaction(SIGINT, &old_interrupt, NULL);
        pthread_mutex_unlock(&process_tree_mutex);
        return error;
    }

    sigset_t signal_mask;
    if (sigprocmask(SIG_SETMASK, NULL, &signal_mask) == -1) {
        int error = errno;
        sigaction(SIGINT, &old_interrupt, NULL);
        sigaction(SIGTERM, &old_terminate, NULL);
        pthread_mutex_unlock(&process_tree_mutex);
        return error;
    }
    sigdelset(&signal_mask, SIGINT);
    sigdelset(&signal_mask, SIGTERM);
    sigset_t default_signals;
    sigemptyset(&default_signals);
    sigaddset(&default_signals, SIGINT);
    sigaddset(&default_signals, SIGTERM);

    posix_spawnattr_t attributes;
    int spawn_error = posix_spawnattr_init(&attributes);
    int attributes_initialized = spawn_error == 0;
    if (spawn_error == 0) {
        spawn_error = posix_spawnattr_setpgroup(&attributes, 0);
    }
    if (spawn_error == 0) {
        spawn_error = posix_spawnattr_setsigmask(&attributes, &signal_mask);
    }
    if (spawn_error == 0) {
        spawn_error = posix_spawnattr_setsigdefault(&attributes, &default_signals);
    }
    if (spawn_error == 0) {
        spawn_error = posix_spawnattr_setflags(
            &attributes,
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        );
    }
    if (spawn_error != 0) {
        if (attributes_initialized) {
            posix_spawnattr_destroy(&attributes);
        }
        sigaction(SIGINT, &old_interrupt, NULL);
        sigaction(SIGTERM, &old_terminate, NULL);
        pthread_mutex_unlock(&process_tree_mutex);
        return spawn_error;
    }

    size_t argument_count = 0;
    if (arguments != NULL) {
        while (arguments[argument_count] != NULL) {
            argument_count++;
        }
    }
    char **child_arguments = (char **)calloc(argument_count + 2, sizeof(char *));
    if (child_arguments == NULL) {
        posix_spawnattr_destroy(&attributes);
        sigaction(SIGINT, &old_interrupt, NULL);
        sigaction(SIGTERM, &old_terminate, NULL);
        pthread_mutex_unlock(&process_tree_mutex);
        return ENOMEM;
    }
    child_arguments[0] = (char *)executable;
    for (size_t index = 0; index < argument_count; index++) {
        child_arguments[index + 1] = (char *)arguments[index];
    }

    pid_t child = 0;
    spawn_error = posix_spawn(
        &child,
        executable,
        NULL,
        &attributes,
        child_arguments,
        environ
    );
    free(child_arguments);
    posix_spawnattr_destroy(&attributes);
    if (spawn_error != 0) {
        sigaction(SIGINT, &old_interrupt, NULL);
        sigaction(SIGTERM, &old_terminate, NULL);
        pthread_mutex_unlock(&process_tree_mutex);
        return spawn_error;
    }

    int child_status = 0;
    int child_reaped = 0;
    int interrupted = 0;
    struct timespec shutdown_started = {0, 0};
    int result = 0;
    for (;;) {
        result = process_tree_reap(child, &child_status, &child_reaped);
        if (result != 0) {
            kill(-child, SIGKILL);
            while (waitpid(child, &child_status, 0) == -1 && errno == EINTR) {
            }
            break;
        }
        if (!interrupted && process_tree_received_signal != 0) {
            interrupted = 1;
            kill(-child, SIGTERM);
            clock_gettime(CLOCK_MONOTONIC, &shutdown_started);
        }
        if (interrupted) {
            struct timespec now;
            clock_gettime(CLOCK_MONOTONIC, &now);
            time_t elapsed_seconds = now.tv_sec - shutdown_started.tv_sec;
            long elapsed_nanoseconds = now.tv_nsec - shutdown_started.tv_nsec;
            if (elapsed_nanoseconds < 0) {
                elapsed_seconds--;
                elapsed_nanoseconds += 1000000000;
            }
            uint64_t elapsed_milliseconds =
                (uint64_t)elapsed_seconds * 1000 + (uint64_t)elapsed_nanoseconds / 1000000;
            if (!process_tree_group_exists(child)) {
                break;
            }
            if (elapsed_milliseconds >= grace_period_milliseconds) {
                kill(-child, SIGKILL);
                if (!child_reaped) {
                    while (waitpid(child, &child_status, 0) == -1 && errno == EINTR) {
                    }
                    child_reaped = 1;
                }
                break;
            }
        } else if (child_reaped) {
            break;
        }
        process_tree_pause();
    }

    sigaction(SIGINT, &old_interrupt, NULL);
    sigaction(SIGTERM, &old_terminate, NULL);
    pthread_mutex_unlock(&process_tree_mutex);
    if (result != 0) {
        return result;
    }
    if (WIFEXITED(child_status)) {
        *exit_status = (int32_t)WEXITSTATUS(child_status);
    } else if (WIFSIGNALED(child_status)) {
        *exit_status = (int32_t)WTERMSIG(child_status);
    } else {
        *exit_status = 1;
    }
    return 0;
}

#endif
