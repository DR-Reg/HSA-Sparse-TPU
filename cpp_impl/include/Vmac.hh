#ifndef __VMAC_HH__
#define __VMAC_HH__

#include <cstdint>
#include <utility>

/*- Actual Vmac unit -*/
/*
 * Functionally similar to MAC
 * except we also store the weight (b)
 * internally when write_enable is on
 * and when write_enable is off, we use
 * the internally stored value instead
 * of input.
 */
template <typename mac_t>
class Vmac
{
private:
    mac_t weight;
public:
    Vmac()
    {
        weight = mac_t::ZERO;
    }
    /* returns <a,a*b + cin>. if wenable is on,
     * b is used as passed parameter, else
     * internal storage b is used.
     * */
    std::pair<mac_t, mac_t> clock(mac_t a, mac_t b, mac_t cin, bool enable, bool wEnable)
    {
        if (!enable) return std::make_pair(mac_t::ZERO, mac_t::ZERO);
        if (wEnable)
            set_weight(b);
        mac_t ret;
        ret.value = a.value*weight.value + cin.value;
        return std::make_pair(a,ret);
    }
    /* This return value should not change,
     * since VPU is weight-stationary
     * */
    mac_t get_mac()
    {
        return weight;
    }
    void set_weight(mac_t w)
    {
        weight.value = w.value;
    }
};
#endif 
