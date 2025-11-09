#ifndef __MAC_T_HH__
#define __MAC_T_HH__
                  
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
#endif 
