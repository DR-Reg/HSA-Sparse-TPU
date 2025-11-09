#ifndef __MAC_HH__
#define __MAC_HH__

#include <cstdint>
#include <utility>

/*- mac type parent -*/
/*
 * For convenience, to define new:
 *   typedef mac_t_p<b> NAME
 * in the main file.
 */
template <uint8_t BitWidth>
struct mac_t_p
{
    uint64_t value : BitWidth;

    static inline const mac_t_p<BitWidth> ZERO = {0};
    friend std::ostream& operator<<(std::ostream& os, const mac_t_p<BitWidth>& v)
    {
        os << v.value;
        return os;
    }
};

/*- Actual mac unit -*/
/*
 * mac_t should be a mac_t_p<b>
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
