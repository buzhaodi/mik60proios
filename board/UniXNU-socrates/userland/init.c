// socrates userland: the first EL0 process on the Redmi K70.
//
// What this is
// ------------
// A complete, self-contained userland image. It is a single static arm64 Mach-O
// file, and it *is* the root device: mockfs (bsd/miscfs/mockfs) presents the
// backing device as /sbin/launchd, so the kernel's load_init_program() execs
// this file as PID 1 and everything below runs as ordinary user processes.
//
// There is no libSystem, no dyld and no shared cache, so nothing here can fall
// back to something the platform happens to provide. Every capability used is
// visible: a syscall number from bsd/kern/syscalls.master and the call site.
//
// What it does
// ------------
//   PID 1 supervises. It prints a boot report from sysctl, proves that the VM
//   can give EL0 anonymous memory, reads the root device back through mockfs,
//   then proves the process model itself before anything fancy: fork() a child
//   that prints "child alive" through the inherited console fd and exits with a
//   distinctive status, and reap it with wait4(). Only then does it fork a shell
//   and a heartbeat and reap them forever. The shell runs builtins against what
//   mockfs exposes; the heartbeat proves that the timer, the scheduler and
//   preemption keep working while PID 1 sleeps in wait4().
//
// What it does not do yet
// -----------------------
// It is not Apple's launchd and does not start SpringBoard. That needs
// AppleAPFS to mount an OS volume, AMFI to accept Apple's signed images and SEP
// for the keybag - three separate pieces of work, each blocked on a driver or a
// service this board does not have yet. What is here is the layer they would sit
// on, and the container format leaves room for them: the same N4KROOT image can
// carry a second file, which is how a real dyld shared cache would be handed to
// a real launchd.

#include "darwin.h"

/* libc.c */
void *memset(void *d, int c, usize n);
void *memcpy(void *d, const void *s, usize n);
usize strlen(const char *s);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, usize n);
int starts_with(const char *s, const char *prefix);
void printf(const char *fmt, ...);
void con_puts(const char *s);
void con_write(const char *s, usize n);
int console_open(void);
void halt_forever(void);

#define VERSION "1.2b"
#define BANNER_WIDTH 62

/* Where the kernel looks for init. mockfs aliases sbin, usr and lib to the root
 * node, so this path resolves to the backing device itself. */
static const char *init_path = "/sbin/launchd";
static const char *data_path = "/probe.bin";   /* second file of the N4KROOT image */

static struct timeval32 boot_time;

static i64 now_seconds(void)
{
	struct timeval32 tv = { 0, 0 };
	sys_gettimeofday(&tv);
	return tv.tv_sec;
}

static i64 uptime_seconds(void)
{
	return now_seconds() - boot_time.tv_sec;
}

/* ---- boot information -------------------------------------------------- */

static void read_sysinfo(struct sysinfo_vals *si)
{
	int  mib[2];
	usize len;

	memset(si, 0, sizeof(*si));

	mib[0] = CTL_HW; mib[1] = HW_NCPU;      len = sizeof(si->ncpu);
	sys_sysctl(mib, 2, &si->ncpu, &len, 0, 0);
	mib[0] = CTL_HW; mib[1] = HW_PAGESIZE;  len = sizeof(si->pagesize);
	sys_sysctl(mib, 2, &si->pagesize, &len, 0, 0);
	mib[0] = CTL_HW; mib[1] = HW_MEMSIZE;   len = sizeof(si->memsize);
	sys_sysctl(mib, 2, &si->memsize, &len, 0, 0);
	mib[0] = CTL_HW; mib[1] = HW_CPUFREQ;   len = sizeof(si->cpufreq);
	sys_sysctl(mib, 2, &si->cpufreq, &len, 0, 0);
	mib[0] = CTL_HW; mib[1] = HW_MACHINE;   len = sizeof(si->machine) - 1;
	sys_sysctl(mib, 2, si->machine, &len, 0, 0);
	mib[0] = CTL_KERN; mib[1] = KERN_OSTYPE; len = sizeof(si->ostype) - 1;
	sys_sysctl(mib, 2, si->ostype, &len, 0, 0);
	mib[0] = CTL_KERN; mib[1] = KERN_VERSION; len = sizeof(si->version) - 1;
	sys_sysctl(mib, 2, si->version, &len, 0, 0);
}

static void print_rule(char c)
{
	char line[BANNER_WIDTH + 2];
	memset(line, c, BANNER_WIDTH);
	line[BANNER_WIDTH] = '\n';
	line[BANNER_WIDTH + 1] = 0;
	con_write(line, BANNER_WIDTH + 1);
}

/* ---- probes ------------------------------------------------------------ */

/* Ask the VM for anonymous memory and actually touch every page. A mapping that
 * faults or is not backed fails here instead of much later. */
static int probe_memory(usize bytes)
{
	const u64    pattern = 0x7665726d656572ULL;   /* "socrates" */
	const usize  step = 4096;
	u8          *p = (u8 *)sys_mmap(0, bytes, PROT_READ | PROT_WRITE,
	                                MAP_PRIVATE | MAP_ANON, -1, 0);

	if (p == MAP_FAILED || (long)p < 0) {
		printf("[mem]  mmap %lu bytes failed\n", (u64)bytes);
		return -1;
	}
	for (usize off = 0; off + sizeof(u64) <= bytes; off += step) {
		*(u64 *)(p + off) = pattern ^ off;
	}
	for (usize off = 0; off + sizeof(u64) <= bytes; off += step) {
		if (*(u64 *)(p + off) != (pattern ^ off)) {
			printf("[mem]  mismatch at offset 0x%x\n", (u64)off);
			sys_munmap(p, bytes);
			return -1;
		}
	}
	printf("[mem]  %lu MiB anonymous, every page written and re-read, at 0x%x\n",
	       (u64)(bytes >> 20), (u64)(usize)p);
	sys_munmap(p, bytes);
	printf("[mem]  unmapped again\n");
	return 0;
}

/* Read a file through mockfs. This is the root device being read back through
 * the filesystem the kernel synthesised for it. */
static ssize read_whole(const char *path, u8 *buf, usize cap)
{
	int   fd = (int)sys_open(path, O_RDONLY, 0);
	usize total = 0;

	if (fd < 0) {
		return fd;
	}
	for (;;) {
		long n = sys_read(fd, buf + total, cap - total);
		if (n <= 0) {
			break;
		}
		total += (usize)n;
		if (total >= cap) {
			break;
		}
	}
	sys_close(fd);
	return (ssize)total;
}

static void probe_root_device(void)
{
	static u8 head[4096];
	ssize n = read_whole(init_path, head, sizeof(head));

	if (n < 0) {
		printf("[fs]   open %s failed (%ld)\n", init_path, (long)n);
		return;
	}
	u32 magic = (u32)head[0] | ((u32)head[1] << 8) | ((u32)head[2] << 16) | ((u32)head[3] << 24);
	printf("[fs]   %s: read %ld bytes, header 0x%x%s\n", init_path, (long)n, (u64)magic,
	       magic == 0xfeedfacf ? " (Mach-O 64)" : "");
}

static void probe_data_file(void)
{
	static u8 buf[8192];
	ssize n = read_whole(data_path, buf, sizeof(buf));

	if (n < 0) {
		printf("[fs]   %s: not present (single-file root image)\n", data_path);
		return;
	}
	printf("[fs]   %s: %ld bytes\n", data_path, (long)n);
	if (n > 0) {
		usize i = 0;
		while (i < (usize)n && buf[i] && buf[i] != '\n' && i < 200) {
			i++;
		}
		if (i > 0) {
			printf("[fs]   first line: ");
			con_write((const char *)buf, i);
			con_puts("\n");
		}
	}
}

/* ---- the multi-process proof --------------------------------------------- */

/* wait4 with a deadline. A blocking wait4 that never returns would freeze the
 * whole boot report, so poll WNOHANG until the deadline passes instead.
 * Returns the last wait4 answer verbatim: pid on a successful reap, a negative
 * errno on failure, 0 if the child is still alive at the deadline. */
static long timed_wait4(long pid, int *status, i64 ms)
{
	struct timeval32 t0 = { 0, 0 };
	sys_gettimeofday(&t0);

	for (;;) {
		int  st = 0;
		long got = sys_wait4(pid, &st, WNOHANG, NULL);

		if (got != 0) {
			if (status) {
				*status = st;
			}
			return got;
		}
		struct timeval32 now = { 0, 0 };
		sys_gettimeofday(&now);
		if ((now.tv_sec - t0.tv_sec) * 1000
		    + (now.tv_usec - t0.tv_usec) / 1000 >= ms) {
			return 0;
		}
	}
}

/* The 2026-11-06 flash (v1.1): fork assigned pid 2 but the child's "child
 * alive" never appeared, and the parent's wait4(2) came back ECHILD - the
 * child vanished kernel-side without ever running user code. So this proof is
 * now two rounds that isolate one variable each:
 *   S: the child exits 43 WITHOUT printing - fork, exit and the zombie path
 *      alone (reaped: st=0x2b00, w4=pid; ECHILD: the child never became a
 *      waitable zombie).
 *   L: the child prints "child alive" through the inherited console fd first,
 *      then exits 42 - adds the write syscall and the console lock to the mix.
 * Both parents print the raw kernel answers verbatim so the screen can be
 * typed back: k0 is kill(pid, 0), 0 = the pid still exists, -3 = ESRCH, gone. */
static void prove_fork_wait(void)
{
	long pid, w4, k0;
	int  st = 0;

	pid = sys_fork();
	if (pid < 0) {
		printf("[fork] fork() failed: %ld\n", pid);
		return;
	}
	if (pid == 0) {
		sys_exit(43);
	}
	w4 = timed_wait4(pid, &st, 3000);
	k0 = sys_kill(pid, 0, 0);
	printf("[fork] S pid=%ld w4=%ld st=0x%x k0=%ld\n", pid, w4, (u64)(u32)st, k0);

	pid = sys_fork();
	if (pid < 0) {
		printf("[fork] fork() failed: %ld\n", pid);
		return;
	}
	if (pid == 0) {
		printf("[fork] child alive: pid=%ld ppid=%ld\n",
		       sys_getpid(), sys_getppid());
		sys_exit(42);
	}
	st = 0;
	w4 = timed_wait4(pid, &st, 3000);
	k0 = sys_kill(pid, 0, 0);
	printf("[fork] L pid=%ld w4=%ld st=0x%x k0=%ld\n", pid, w4, (u64)(u32)st, k0);
}

/* ---- shell ------------------------------------------------------------- */

static int read_line(char *line, usize cap)
{
	usize n = 0;

	for (;;) {
		char c = 0;
		long r = sys_read(0, &c, 1);
		if (r <= 0) {
			return (int)r;
		}
		if (c == '\r') {
			continue;
		}
		if (c == '\n') {
			con_puts("\n");
			line[n] = 0;
			return (int)n;
		}
		if ((c == 0x7f || c == 0x08) && n > 0) {
			n--;
			con_puts("\b \b");
			continue;
		}
		if (n + 1 < cap) {
			line[n++] = c;
			con_write(&c, 1);
		}
	}
}

static void cmd_help(void)
{
	con_puts(
		"commands:\n"
		"  help            this list\n"
		"  sysinfo         cpu, memory, page size, kernel version\n"
		"  mem             anonymous mmap and page-touch test\n"
		"  ls              what mockfs exposes as the root\n"
		"  cat PATH        read a file through mockfs\n"
		"  ps              processes this init is supervising\n"
		"  uptime          seconds since init started\n"
		"  echo TEXT       print TEXT\n"
		"  fork            fork a child that reports and exits\n"
		"  sh / hb         start another shell or heartbeat\n"
		"  reboot          ask the kernel to reboot\n"
		"  exit            leave this shell\n");
}

static void cmd_ls(void)
{
	con_puts("/            (mockfs root)\n");
	con_puts("/sbin        -> root, so /sbin/launchd is this image\n");
	con_puts("/dev         devfs\n");
	con_puts("/launchd     root device as a file\n");
	con_puts("/probe.bin   second file of the N4KROOT image, if present\n");
	con_puts("/dyld        alias of the same second file\n");
	con_puts("no other paths exist: mockfs is read-only and has a fixed tree\n");
}

static void cmd_sysinfo(void)
{
	struct sysinfo_vals si;
	read_sysinfo(&si);
	printf("cpu          %ld\n", si.ncpu);
	printf("page size    %ld bytes\n", si.pagesize);
	printf("memory       %ld MiB\n", si.memsize >> 20);
	printf("cpu freq     %ld MHz\n", si.cpufreq ? si.cpufreq / 1000000 : 0);
	printf("machine      %s\n", si.machine);
	printf("ostype       %s\n", si.ostype);
	printf("version      %s\n", si.version);
}

static void cmd_cat(const char *path)
{
	static u8 buf[4096];
	ssize n = read_whole(path, buf, sizeof(buf) - 1);

	if (n < 0) {
		printf("cat: %s: error %ld\n", path, (long)n);
		return;
	}
	buf[n] = 0;
	con_write((const char *)buf, (usize)n);
	if (n == 0 || buf[n - 1] != '\n') {
		con_puts("\n");
	}
}

struct task {
	int          pid;
	const char  *name;
};

#define MAX_TASKS 8
static struct task tasks[MAX_TASKS];
static int         task_count;

static void cmd_ps(void)
{
	printf("PID  COMMAND      STATE\n");
	printf("%ld init running\n", sys_getpid());
	for (int i = 0; i < task_count; i++) {
		printf("%d %s supervised\n", tasks[i].pid, tasks[i].name);
	}
}

static void child_report(void)
{
	printf("[fork] child pid=%ld ppid=%ld: forked from a user process, exiting 0\n",
	       sys_getpid(), sys_getppid());
	sys_exit(0);
}

static void run_command(char *line)
{
	char *arg = line;
	while (*arg == ' ') {
		arg++;
	}
	if (!*arg) {
		return;
	}

	if (!strcmp(arg, "help")) {
		cmd_help();
	} else if (!strcmp(arg, "sysinfo")) {
		cmd_sysinfo();
	} else if (!strcmp(arg, "mem")) {
		probe_memory(1 << 20);
	} else if (!strcmp(arg, "ls")) {
		cmd_ls();
	} else if (!strcmp(arg, "ps")) {
		cmd_ps();
	} else if (!strcmp(arg, "uptime")) {
		printf("up %ld s\n", uptime_seconds());
	} else if (!strcmp(arg, "fork")) {
		if (sys_fork() == 0) {
			child_report();
		}
	} else if (!strcmp(arg, "reboot")) {
		printf("reboot: asking the kernel\n");
		sys_reboot(RB_AUTOBOOT);
		halt_forever();
	} else if (!strcmp(arg, "exit")) {
		con_puts("shell: leaving\n");
		sys_exit(0);
	} else if (starts_with(arg, "cat ")) {
		cmd_cat(arg + 4);
	} else if (starts_with(arg, "echo ")) {
		con_puts(arg + 5);
		con_puts("\n");
	} else {
		printf("%s: not a builtin. `help` lists them.\n", arg);
	}
}

static void role_shell(void)
{
	char line[128];

	printf("[sh]   pid=%ld, reading /dev/console\n", sys_getpid());
	con_puts("socrates> ");
	for (;;) {
		int n = read_line(line, sizeof(line));
		if (n < 0) {
			printf("[sh]   read: %d, no input device attached yet\n", n);
			con_puts("[sh]   waiting: connect a keyboard or the GT9916S driver and this becomes interactive\n");
			halt_forever();
		}
		if (n == 0) {
			con_puts("socrates> ");
			continue;
		}
		run_command(line);
		con_puts("socrates> ");
	}
}

static void role_heartbeat(void)
{
	u64 ticks = 0;
	printf("[hb]   pid=%ld, ticking every 10 s\n", sys_getpid());
	for (;;) {
		sys_nanosleep(10, 0);
		printf("[hb]   tick %lu, uptime %ld s\n", ++ticks, uptime_seconds());
	}
}

/* Fork a role, and have the child re-exec this same image for it. The exec is
 * the interesting part: it walks open/load_machfile/AMFI again from a user
 * process, which is the path any real service would take. */
static int spawn(const char *role)
{
	long pid = sys_fork();

	if (pid != 0) {
		return (int)pid;
	}

	char *argv[3];
	char *envp[2];
	argv[0] = (char *)init_path;
	argv[1] = (char *)role;
	argv[2] = NULL;
	envp[0] = (char *)"PATH=/usr/bin:/bin:/sbin";
	envp[1] = NULL;
	long ret = sys_execve(init_path, argv, envp);

	/* Exec refused: still honour the role rather than die silently. The errno
	 * makes this legible on screen: a fresh "[hb]/[sh] pid=N" line without it
	 * means the exec worked; this line means the exec was refused and the
	 * forked child is running the role in-process. */
	printf("[fork] execve refused: %ld - running the %s role in-process\n", ret, role);
	if (!strcmp(role, "sh")) {
		role_shell();
	} else {
		role_heartbeat();
	}
	sys_exit(1);
	return 0;
}

static void role_supervisor(void)
{
	struct sysinfo_vals si;

	console_open();
	boot_time.tv_sec = now_seconds();

	print_rule('=');
	con_puts("  socrates userland " VERSION "  -  first EL0 process on the K70\n");
	print_rule('=');
	printf("[init] pid=%ld ppid=%ld uid=%ld euid=%ld\n", sys_getpid(), sys_getppid(),
	       sys_getuid(), sys_geteuid());
	printf("[init] console fd=%d\n", console_open());

	read_sysinfo(&si);
	printf("[hw]   %ld cpus, %ld MiB ram, %ld byte pages\n", si.ncpu, si.memsize >> 20, si.pagesize);
	printf("[os]   %s\n", si.version);

	probe_memory(1 << 20);
	probe_root_device();
	probe_data_file();

	prove_fork_wait();

	con_puts("[init] starting services\n");
	tasks[0].pid = spawn("hb"); tasks[0].name = "hb"; task_count = 1;
	printf("[init] hb    -> pid %d\n", tasks[0].pid);

	tasks[1].pid = spawn("sh"); tasks[1].name = "sh"; task_count = 2;
	printf("[init] sh    -> pid %d\n", tasks[1].pid);

	con_puts("[init] supervising: wait4() forever, respawning anything that exits\n");
	printf("[init] ready. uptime %ld s\n", uptime_seconds());

	/* The 2026-11-06 flash: children forked (pids assigned) but no child ever
	 * printed, and a blocking wait4 hung silently. So this loop trusts nothing
	 * that could freeze: it polls WNOHANG on its own gettimeofday clock (no
	 * nanosleep - a broken timer cannot hide here) and prints one line every
	 * 5 s. The boot CPU is proven alive; if these lines stop, the freeze is
	 * the supervisor itself. hb/sh are kill(pid, 0) probes of the services:
	 * 0 = the child exists and is stuck somewhere, -3 = it is gone.
	 *
	 * The v1.2 tripwire (init exited at 60 s to force a panic that dumped the
	 * fault record) is retired in v1.2b: the dump was collected - every slot
	 * zero, the children never fault - so the panic now buys nothing, while
	 * each deliberate kernel crash leaves the ABL/PMIC pollution that makes
	 * the NEXT flash a silent entry reset. With no tripwire this console
	 * stays up indefinitely: transcribe at leisure. */
	for (;;) {
		i64 next = uptime_seconds() + 5;
		while (uptime_seconds() < next) {
			/* busy wait by design */
		}
		int  st = 0;
		long pid = sys_wait4(-1, &st, WNOHANG, NULL);
		long hb = (task_count > 0 && tasks[0].pid > 0) ? sys_kill(tasks[0].pid, 0, 0) : 0;
		long sh = (task_count > 1 && tasks[1].pid > 0) ? sys_kill(tasks[1].pid, 0, 0) : 0;
		printf("[init] alive %ld s w4=%ld hb=%ld sh=%ld\n",
		       uptime_seconds(), pid, hb, sh);

		if (pid > 0) {
			for (int i = 0; i < task_count; i++) {
				if (tasks[i].pid == (int)pid) {
					printf("[init] %s (pid %ld) exited, status 0x%x; respawning\n",
					       tasks[i].name, pid, (u64)(u32)st);
					tasks[i].pid = spawn(tasks[i].name);
					printf("[init] %s -> pid %d\n", tasks[i].name, tasks[i].pid);
				}
			}
		}
	}
}

/* ---- entry ------------------------------------------------------------- */

/* Called from start.S with the Darwin process stack pointer. */
void entry(u64 *stack)
{
	int    argc = (int)stack[0];
	char **argv = (char **)&stack[1];

	console_open();
	/* Every run of this image announces its argv: PID 1 arrives with argc=1
	 * from the kernel's exec, the hb/sh services arrive here again through
	 * spawn()'s execve with argv[1] set, and an unexpected re-exec of PID 1
	 * would show up as repeated argc=1 lines. */
	printf("[init] entry pid=%ld argc=%ld argv1=%s\n",
	       sys_getpid(), (i64)argc, argv[1] ? argv[1] : "-");
	/* A role started by exec is a new process; its uptime starts here. */
	if (boot_time.tv_sec == 0) {
		boot_time.tv_sec = now_seconds();
	}

	if (argv[1]) {
		if (!strcmp(argv[1], "sh")) {
			role_shell();
		} else if (!strcmp(argv[1], "hb")) {
			role_heartbeat();
		}
	}

	if (sys_getpid() == 1) {
		role_supervisor();
	}
	/* Not PID 1 and no role: this is a stray exec. Be a shell. */
	role_shell();
	halt_forever();
}
