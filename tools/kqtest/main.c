// kqtest — chạy trên máy iOS 6: kiểm kqueue EVFILT_USER (bộ đánh thức của mio / tokio trên Apple) có đánh thức được luồng
// đang chờ kevent không. So với cách đánh thức bằng pipe.
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/event.h>
#include <sys/time.h>
#include <unistd.h>

static int kq;
static int pipefd[2];

static double now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

static void *trigger_user(void *arg) {
    usleep(200 * 1000);
    struct kevent ev;
    EV_SET(&ev, 7, EVFILT_USER, 0, NOTE_TRIGGER, 0, NULL);
    int r = kevent(kq, &ev, 1, NULL, 0, NULL);
    printf("  NOTE_TRIGGER → %d (errno %d %s)\n", r, r < 0 ? errno : 0, r < 0 ? strerror(errno) : "");
    return NULL;
}

static void *trigger_pipe(void *arg) {
    usleep(200 * 1000);
    char c = 1;
    write(pipefd[1], &c, 1);
    return NULL;
}

static void wait_once(const char *name) {
    struct kevent out;
    struct timespec ts = {3, 0};
    double t0 = now_ms();
    int n = kevent(kq, NULL, 0, &out, 1, &ts);
    printf("%s: kevent trả %d sau %.0f ms (filter %d, ident %lu)\n", name, n, now_ms() - t0, n > 0 ? out.filter : 0,
           n > 0 ? (unsigned long)out.ident : 0);
}

int main(void) {
    kq = kqueue();
    struct kevent ev;
    EV_SET(&ev, 7, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, NULL);
    int r = kevent(kq, &ev, 1, NULL, 0, NULL);
    printf("đăng ký EVFILT_USER → %d (errno %d %s)\n", r, r < 0 ? errno : 0, r < 0 ? strerror(errno) : "");
    pthread_t th;
    pthread_create(&th, NULL, trigger_user, NULL);
    wait_once("EVFILT_USER");
    pthread_join(th, NULL);

    pipe(pipefd);
    EV_SET(&ev, pipefd[0], EVFILT_READ, EV_ADD | EV_CLEAR, 0, 0, NULL);
    kevent(kq, &ev, 1, NULL, 0, NULL);
    pthread_create(&th, NULL, trigger_pipe, NULL);
    wait_once("pipe");
    pthread_join(th, NULL);
    return 0;
}
