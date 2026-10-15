// exdiff/driver.c — process entry for shimmed upstream C examples (see
// shim.h). shim.h renames the example's main(); the hooks it redirects to
// live in hooks.c (shared with the Zig-API example gate).

int exdiff_example_main(void);

int main(void)
{
    return exdiff_example_main();
}
