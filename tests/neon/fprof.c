/* QEMU plugin: instructions executed per function (from nm -S -n output).
 *   -plugin ./libfprof.so,syms=FILE,out=FILE                              */
#include <glib.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

typedef struct { uint64_t start, end; char *name; uint64_t insns, calls; } Sym;
typedef struct { uint64_t pc, n, count; Sym *sym; } TB;
static Sym *syms;
static size_t nsyms;
static GPtrArray *tbs;
static GMutex lock;
static char *outpath;
static Sym other = { 0, 0, "(other)", 0, 0 };

static Sym *find(uint64_t pc)
{
    size_t lo = 0, hi = nsyms;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (syms[mid].start <= pc) lo = mid + 1; else hi = mid;
    }
    if (lo && pc < syms[lo - 1].end) return &syms[lo - 1];
    return &other;
}

static void tb_exec(unsigned int vcpu, void *udata)
{
    TB *t = udata;
    __atomic_fetch_add(&t->count, 1, __ATOMIC_RELAXED);
}

static void tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
    TB *t = g_new0(TB, 1);
    t->pc = qemu_plugin_tb_vaddr(tb);
    t->n = qemu_plugin_tb_n_insns(tb);
    t->sym = find(t->pc);
    g_mutex_lock(&lock);
    g_ptr_array_add(tbs, t);
    g_mutex_unlock(&lock);
    qemu_plugin_register_vcpu_tb_exec_cb(tb, tb_exec, QEMU_PLUGIN_CB_NO_REGS, t);
}

static int cmp(const void *a, const void *b)
{
    const Sym *x = *(Sym * const *)a, *y = *(Sym * const *)b;
    return x->insns < y->insns ? 1 : x->insns > y->insns ? -1 : 0;
}

static void at_exit(qemu_plugin_id_t id, void *p)
{
    uint64_t total = 0;
    for (guint i = 0; i < tbs->len; i++) {
        TB *t = g_ptr_array_index(tbs, i);
        t->sym->insns += t->count * t->n;
        if (t->pc == t->sym->start) t->sym->calls += t->count;
        total += t->count * t->n;
    }
    Sym **v = g_new(Sym *, nsyms + 1);
    for (size_t i = 0; i < nsyms; i++) v[i] = &syms[i];
    v[nsyms] = &other;
    qsort(v, nsyms + 1, sizeof(*v), cmp);
    FILE *f = fopen(outpath, "w");
    fprintf(f, "total %" PRIu64 "\n", total);
    for (size_t i = 0; i <= nsyms && v[i]->insns; i++)
        fprintf(f, "%" PRIu64 " %" PRIu64 " %s\n", v[i]->insns, v[i]->calls, v[i]->name);
    fclose(f);
}

QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id, const qemu_info_t *info,
                                           int argc, char **argv)
{
    const char *sympath = NULL;
    for (int i = 0; i < argc; i++) {
        if (!strncmp(argv[i], "syms=", 5)) sympath = argv[i] + 5;
        else if (!strncmp(argv[i], "out=", 4)) outpath = g_strdup(argv[i] + 4);
    }
    if (!sympath || !outpath) return -1;
    FILE *f = fopen(sympath, "r");
    if (!f) return -1;
    char line[512];
    size_t cap = 0;
    while (fgets(line, sizeof(line), f)) {
        char name[400], type;
        uint64_t a, s;
        if (sscanf(line, "%" SCNx64 " %" SCNx64 " %c %399s", &a, &s, &type, name) != 4) continue;
        if (type != 'T' && type != 't') continue;
        if (nsyms == cap) { cap = cap ? cap * 2 : 4096; syms = realloc(syms, cap * sizeof(Sym)); }
        a &= ~1ull;
        syms[nsyms++] = (Sym){ a, a + s, g_strdup(name), 0, 0 };
    }
    fclose(f);
    tbs = g_ptr_array_new();
    qemu_plugin_register_vcpu_tb_trans_cb(id, tb_trans);
    qemu_plugin_register_atexit_cb(id, at_exit, NULL);
    return 0;
}
