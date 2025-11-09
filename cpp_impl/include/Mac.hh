#ifndef __MAC_HH__
#define __MAC_HH__

#include <cstdint>
#include <utility>

/*- Mac unit -*/
/*
 * mac_t should be a mac_t_p<b>
 *
 * This Mac Unit operates in a
 * Output Stationary manner, since the results
 * are stored internally.
 */
template <typename mac_t>
class Mac
{
private:
    mac_t value;
public:
    Mac()
    {
        value = mac_t::ZERO;
    }
    /* returns a and b if enabled, else zeros */
    std::pair<mac_t, mac_t> clock(mac_t a, mac_t b, bool enable)
    {
        if (!enable) return std::make_pair(mac_t::ZERO, mac_t::ZERO);
        value.value += a.value*b.value;
        return std::make_pair(a,b);
    }
    mac_t get_mac()
    {
        return value;
    }
};


#endif
