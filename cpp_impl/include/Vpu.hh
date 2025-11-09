#ifndef __VPU_HH__
#define __VPU_HH__

#include <cstdint>
#include <cstdlib>

#include "Vmac.hh"

/*- Vector Processing Unit *-/
 * mac_t should be a mac_t_p<b> 
 *
 * VPU 'shape' must be specified a priori:
 * using parameter N (will be NxN)
 *
 * Full implementation in header to avoid explicit
 * instantiation due to non-template type params (nttp)
 *
 * Performs the vector multiplication 
 */
template <typename mac_t, uint64_t N>
class Vpu
{
    private:
        uint64_t counter;
        bool enabled[N][N]; // only used for debug
 
        mac_t acts_sram[N], weights_sram[N][N];
        mac_t init_acts_sram[N][N], init_weights_sram[N][N];
        Vmac<mac_t> vmac_units[N][N]; 
        mac_t right_latches[N][N];  // for left-right streaming of psums
        mac_t down_latches[N][N];  // for top-down streaming of acts
    public:
        Vpu(mac_t acts_sram_p[N], mac_t weights_sram_p[N][N])
        {
            memcpy(init_acts_sram, acts_sram_p, N*sizeof(mac_t)); 
            for (uint64_t i = 0; i < N; i++)
                memcpy(init_weights_sram[i], weights_sram_p[i], N*sizeof(mac_t)); 
            reset();
        }
        void reset()
        {
            memcpy(acts_sram, init_acts_sram, N*sizeof(mac_t)); 
            for (uint64_t i = 0; i < N; i++)
                memcpy(weights_sram[i], init_weights_sram[i], N*sizeof(mac_t));  
            counter = 0;
        }

        void print_mac_values()
        {
            for (int i = 0; i < N; i++)
            {
                for (int j = 0; j < N; j++)
                    std::cout << "| " << vmac_units[i][j].get_mac().value << " ";
                std::cout << "|" << std::endl;
            }
        }
       
        void clock()
        {
            std::pair<mac_t, mac_t> outputs[N][N];
            for (uint64_t i = 0; i < N; i++)
                for (uint64_t j = 0; j < N; j++)
                {
                    /* No pipelining for now,
                     * so each vmac only active for
                     * 1 cycle... In pipelining case,
                     * the next vector to be multiplied
                     * begins streaming behind this one.
                     */
                    bool enable = (i+j)==counter;
                    enabled[i][j] = enable;
                    if (!enable) continue;
                    mac_t input_top_a, input_left_cin;
                        
                    input_left_cin = j == 0 ? mac_t::ZERO : right_latches[i][j-1];
                    input_top_a = i == 0 ? acts_sram[j] : down_latches[i-1][j];

                    /* Weight-stationary */
                    mac_t input_top =  weights_sram[i][j];

                    /* I don't simulate the staggered reading,
                     * but since vmac units store the read,
                     * only one value from each weight row has
                     * to be read at once at most (each weight
                     * row should be in separate sram). Here,
                     * just imagine we have infty read ports
                     * */
                    outputs[i][j] = vmac_units[i][j].clock(
                        input_top_a,
                        input_top,
                        input_left_cin,
                        enable,
                        true
                    );
                }

            /* Update latch values, after so no weirdness 
             * Could probably figure out a loop order to
             * do this above, but this works fine.
             * Only right to latch if enabled */
            for (uint64_t i = 0; i < N; i++)
                for (uint64_t j = 0; j < N; j++)
                    if (enabled[i][j])
                    {
                        down_latches[i][j] = outputs[i][j].first;
                        right_latches[i][j] = outputs[i][j].second;
                    }
            counter++;
        }
        std::string to_string()
        {
            /* Format (ala = acts latch):
             *
             * ===============================================
             * |    W1,1,ala  |------|    W1,2,ala   |------|
             * -----------------------------------------------
             * |    PSUM      | psum |    PSUM       | psum |
             * etc..
             * Could figure out the prealloc size... but I don't want to.
             * So I use cpp string (and inefficiently)
             * */
            std::string top_rows[N], bot_rows[N];
            uint64_t max_row_width = 0;
            for (uint64_t i = 0; i < N; i++)
            {
                std::string top_row, bot_row;
                for (uint64_t j = 0; j < N; j++)
                {
                    mac_t ala;
                    mac_t psum;
                    ala = down_latches[i][j];
                    psum = right_latches[i][j];
                    std::string psum_str, ala_str, w_str;
                    ala_str = std::to_string(psum.value);
                    w_str   = std::to_string(weights_sram[i][j].value) + "↓";
                    psum_str = !enabled[i][j] ? "Disabled" :
                        //std::to_string(vmac_units[i][j].get_mac().value);
                        std::format("{}x{}+{}",
                            std::to_string(ala.value),
                            w_str,
                            std::to_string(psum.value-(ala.value*weights_sram[i][j].value))
                        );
                    w_str += "," + std::to_string(ala.value);
                    uint64_t pwidth = psum_str.length();
                    uint64_t bwidth = w_str.length();
                    uint64_t twidth = std::max(std::max(pwidth, bwidth), 8LLU) + 2;
                    std::string ppsum_str = std::vformat("{:^"+std::to_string(twidth)+"}", std::make_format_args(psum_str));
                    std::string mw_str = std::vformat("{:^"+std::to_string(twidth)+"}", std::make_format_args(w_str));
                    top_row += "| " + mw_str + " |" + std::string(ala_str.length()+2, '-');
                    bot_row += "| " + ppsum_str + " | " + ala_str + " ";
                }
                top_rows[i] = top_row;
                bot_rows[i] = bot_row;
                max_row_width = top_row.length() > max_row_width ? top_row.length() : max_row_width;
            }
            std::string ret;
            uint64_t max_l_width = 0;
            for (uint64_t i = 0; i < N; i++)
                max_l_width = std::max(max_l_width, (uint64_t)std::to_string(acts_sram[i].value).length());
            max_l_width += 5;
            std::string lsep = std::string(max_l_width, ' ');
            // std::string sep = lsep+std::string(max_row_width+1, '=');
            std::string sep = " "+std::string(max_row_width+1, '=');
            // ret += lsep+toptop_row + "\n" + sep + "\n";
            for (uint64_t i = 0; i < N; i++)
                // ret += " " + std::to_string(acts_sram[i].value) + " -> " + top_rows[i] + "|\n" + \
                        lsep + bot_rows[i] + "|\n" + sep + "\n";
                ret += " " + top_rows[i] + "|\n" + \
                        " " + bot_rows[i] + "|\n" + sep + "\n";
            return ret;
    }
    /* Kind of bad practice to allocate
     * inside a function, should make sure
     * to free whenever I call this
     * */
    mac_t* get_result()
    {
        mac_t *ret = (mac_t *)malloc(N * sizeof(mac_t));
        for (uint64_t i = 0; i < N; i++)
            ret[i] = right_latches[i][N-1];
        return ret;
    }
};

#endif
