#include "axiom.h"

int main(int argc, char** argv) {
    (void)argc; (void)argv;

    int any = 0;
    for (unsigned int i = 0; ; i++) {
        struct pci_device_args d;
        d.index = i;
        d.result = 0;
        ax_pci_get_device(&d);
        if (!d.result) break;
        any = 1;

        ax_printf("%02x:%02x.%x  %04x:%04x  %s\n",
                   d.bus, d.device, d.function, d.vendor_id, d.device_id, d.class_name);
    }

    if (!any) {
        ax_print("No PCI devices found (or denied - see 'avc: denied { pci_raw }' above).\n");
    }
    return 0;
}
