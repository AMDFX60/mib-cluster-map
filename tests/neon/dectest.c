/* Decodes an Annex B H.264 file the way stream-player does (parser, low
 * delay, fast, loop filter skipped on non-reference pictures) and prints an
 * MD5 of every picture's visible planes.
 *   dectest [-c] [-q] [-t threads] [-d] [-T] file
 *   -c  C code only (no NEON), the reference
 *   -q  no per-picture MD5s and no MD5 work at all (for profiling)
 *   -d  loop filter on every picture (not only reference ones)
 *   -T  deblocking on its own thread (tools/ffmpeg_deblock_thread.patch),
 *       as the player does from 1.4.2-beta2; its statistics on stderr      */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libavcodec/avcodec.h>
#include <libavutil/cpu.h>
#include <libavutil/md5.h>
#include <libavutil/mem.h>

#include <signal.h>
#include <ucontext.h>

/* In FFmpeg with tools/ffmpeg_deblock_thread.patch only (weak: c6 and orig
 * have none). */
extern int mibcm_h264_deblock_thread __attribute__((weak));
extern volatile unsigned mibcm_h264_dbt_rows_thread __attribute__((weak));
extern volatile unsigned mibcm_h264_dbt_rows_decoder __attribute__((weak));
extern volatile unsigned mibcm_h264_dbt_waits __attribute__((weak));
extern volatile int mibcm_h264_dbt_state __attribute__((weak));

static struct AVMD5 *g_all;
static int g_quiet, g_frames;

/* Says where a fault happened (pc and address), for the strict emulator. */
static void on_fault(int sig, siginfo_t *si, void *uc)
{
    char msg[96];
#ifdef __arm__
    unsigned long pc = (unsigned long)((ucontext_t *)uc)->uc_mcontext.arm_pc;
#else
    unsigned long pc = 0;   /* the PC build (C code, deblocking thread checks) */
#endif
    int n = snprintf(msg, sizeof(msg), "FAULT sig=%d pc=%#lx addr=%p\n", sig, pc, si->si_addr);
    write(2, msg, n);
    _exit(128 + sig);
}

static void picture(const AVFrame *f)
{
    g_frames++;
    if (g_quiet)
        return;
    struct AVMD5 *m = av_md5_alloc();
    uint8_t d[16];
    char hex[33];
    av_md5_init(m);
    for (int p = 0; p < 3; p++) {
        int w = p ? (f->width + 1) >> 1 : f->width;
        int h = p ? (f->height + 1) >> 1 : f->height;
        for (int y = 0; y < h; y++)
            av_md5_update(m, f->data[p] + (ptrdiff_t)y * f->linesize[p], w);
    }
    av_md5_final(m, d);
    av_free(m);
    for (int i = 0; i < 16; i++)
        sprintf(hex + 2 * i, "%02x", d[i]);
    printf("%d %dx%d %s\n", g_frames, f->width, f->height, hex);
    av_md5_update(g_all, d, 16);
}

static void drain(AVCodecContext *c, AVFrame *f)
{
    while (avcodec_receive_frame(c, f) == 0) {
        picture(f);
        av_frame_unref(f);
    }
}

int main(int argc, char **argv)
{
    int force_c = 0, threads = 1, all_deblock = 0, dbt = 0, o;
    while ((o = getopt(argc, argv, "cqt:dT")) != -1) {
        if (o == 'T') { dbt = 1; continue; }
        if (o == 'c') force_c = 1;
        else if (o == 'q') g_quiet = 1;
        else if (o == 't') threads = atoi(optarg);
        else if (o == 'd') all_deblock = 1;
        else return 2;
    }
    if (optind >= argc) return 2;
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = on_fault;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGSEGV, &sa, NULL);
    if (force_c)
        av_force_cpu_flags(0);
    if (dbt) {
        if (!&mibcm_h264_deblock_thread) {
            fprintf(stderr, "-T: this FFmpeg has no deblocking thread\n");
            return 2;
        }
        mibcm_h264_deblock_thread = 1;
    }
    FILE *in = fopen(argv[optind], "rb");
    if (!in) { perror(argv[optind]); return 1; }
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_H264);
    AVCodecParserContext *parser = av_parser_init(codec->id);
    AVCodecContext *c = avcodec_alloc_context3(codec);
    c->thread_count = threads;
    c->thread_type = FF_THREAD_SLICE;
    c->flags |= AV_CODEC_FLAG_LOW_DELAY;
    c->flags2 |= AV_CODEC_FLAG2_FAST;
    c->skip_loop_filter = all_deblock ? AVDISCARD_DEFAULT : AVDISCARD_NONREF;
    if (avcodec_open2(c, codec, NULL) < 0) return 1;
    g_all = av_md5_alloc();
    av_md5_init(g_all);
    AVPacket *pkt = av_packet_alloc();
    AVFrame *f = av_frame_alloc();
    static uint8_t buf[4096 + AV_INPUT_BUFFER_PADDING_SIZE];
    int eof = 0;
    while (!eof) {
        size_t n = fread(buf, 1, 4096, in);
        memset(buf + n, 0, AV_INPUT_BUFFER_PADDING_SIZE);
        eof = n == 0;
        uint8_t *p = buf;
        int left = (int)n;
        do {
            int used = av_parser_parse2(parser, c, &pkt->data, &pkt->size, p, left,
                                        AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
            p += used;
            left -= used;
            if (pkt->size && avcodec_send_packet(c, pkt) == 0)
                drain(c, f);
        } while (left > 0 || (eof && pkt->size));
    }
    avcodec_send_packet(c, NULL);
    drain(c, f);
    uint8_t d[16];
    av_md5_final(g_all, d);
    printf("frames %d all ", g_frames);
    for (int i = 0; i < 16; i++)
        printf("%02x", d[i]);
    printf("\n");
    avcodec_free_context(&c);
    av_parser_close(parser);
    if (dbt)
        fprintf(stderr, "deblocking thread: state %d, rows %u on the thread, %u on the decoder, %u waits\n",
                mibcm_h264_dbt_state, mibcm_h264_dbt_rows_thread, mibcm_h264_dbt_rows_decoder,
                mibcm_h264_dbt_waits);
    return 0;
}
