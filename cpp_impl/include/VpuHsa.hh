#ifndef __VPUHSA_HH__
#define __VPUHSA_HH__ 

#include <cstdint>
#include <cstdlib>

#include "WsMac.hh"

/*- Vector Processing Unit -- HSA Dataflow Style *-/
 * mac_t should be a mac_t_p<b>
 *
 * VPU shaped specified a priori: NxN
 *
 * Full implementation in header to avoid nttp
 *
 * Performs vector multiplication with the same
 * type of dataflow as a HSA module would when in MVM
 * mode. It is NOT itself part of the HSA module.
 *
 * The HSA in MVM mode works as follows:
 * - Weights are stationary in each MAC (why we use WsMac)
 * - activation vector value a_i broadcast to row
 *   i in cycle i (rest of rows are idle) 
 * - partial sums flow top to bottom
 *
 * The VPU does not need to have ALL of the rows as
 * it never operates in MMM mode. We can have
 * a single row with a single row of latches below
 * which feed back in as input to the same row.
 * HOWEVER, this would require each MAC having some
 * extra memory (as each row has different w values)
 * So, it is implemented here as a grid. I.e. this
 * module is essentially the HSA fixed to MVM mode.
 * 
 * Then results are collected at the end, and they
 * all come in at the same time (hence the benefit
 * over using MMM mode for vect mult)
 */
template <typename mac_t, uint64_t N>
class VpuHsa
{
private:
    uint64_t counter;
    bool enabled[N][N];
    mac_t top_values[N]; // only used for debug, represent nothing (Cin==0 for top)
    mac_t left_values[N]; // only used for debug, represent broadcast

    mac_t acts_sram[N], weights_sram[N][N];
    mac_t init_acts_sram[N], init_weights_sram[N][N];
    WsMac<mac_t> mac_units[N][N]; 
    mac_t down_latches[N][N];  // for top-down streaming of psums
       
public:
    VpuHsa(mac_t acts_sram_p[N], mac_t weights_sram_p[N][N])
    {
        for (uint64_t i = 0; i < N; i++)
            init_acts_sram[i] = acts_sram_p[i];
        /* Weights needs to be transposed for this dataflow style */
        for (uint64_t i = 0; i < N; i++)
            for (uint64_t j = 0; j < N; j++)
                init_weights_sram[i][j] =  weights_sram_p[j][i];
        reset();
    }

    void reset()
    {
        for (uint64_t i = 0; i < N; i++)
            acts_sram[i] =  init_acts_sram[i];
        for (uint64_t i = 0; i < N; i++)
            memcpy(weights_sram[i], init_weights_sram[i], N*sizeof(mac_t));  
        counter = 0;
        for (uint64_t i = 0; i < N; i++)
            top_values[i] = mac_t::ZERO;
        for (uint64_t j = 0; j < N; j++) 
            left_values[j] = acts_sram[j];
    }

    void clock()
    {
        std::pair<mac_t, mac_t> outputs[N][N];
        for (uint64_t i = 0; i < N; i++)
            for (uint64_t j = 0; j < N; j++)
            {
                /* We operate a row at a time, so in cycle 1, row 1 enabled
                 * cycle 2 row 2 enabled... Thus enabled iff counter==i
                 * */
                bool enable = counter==i;
                enabled[i][j] = enable;
                if (!enable)
                {
                    left_values[i] = mac_t::ZERO;
                    continue;
                }

                /* The same activation input (a[i])
                 * should be broadcast to all the
                 * macs
                 * */
                mac_t input_broad_a, input_top_cin;
                    
                input_top_cin = i == 0 ? mac_t::ZERO : down_latches[i-1][j];
                input_broad_a = acts_sram[i];

                /* Weight-stationary */
                mac_t input_weight =  weights_sram[i][j];

                /* I don't simulate the weight initialisation
                 * into each PE (which should occur over multiple
                 * cycles, and ideally be pipelined with the own
                 * VPU operation - which is way easier in MVM
                 * mode than MMM)
                 **/
                outputs[i][j] = mac_units[i][j].clock(
                    input_broad_a,
                    input_weight,
                    input_top_cin,
                    enable,
                    true
                );

                /* Top values always gets 0, cin starts at 0*/
                top_values[j] = mac_t::ZERO;
                left_values[i] = acts_sram[i];  
            }

        /* Update latch values, after so no weirdness 
         * Could probably figure out a loop order to
         * do this above, but this works fine.
         * Only right to latch if enabled */
        for (uint64_t i = 0; i < N; i++)
            for (uint64_t j = 0; j < N; j++)
                if (enabled[i][j])
                {
                    /* Don't need to use first (acts)
                     * as that value of acts is
                     * used all at once
                     **/
                    down_latches[i][j] = outputs[i][j].second;
                    /* Last row => Output generated,
                     * no need for separate structure
                     * as it will be in down_latches */
                }
        counter++;
    }

    std::string to_string()
    {
        /* Format (pla = partial latch, ala = acts latch):
         * =======================
         * |    W1,1   ||   W1,2 |
         * -----------------------
         * |    pla    ||   pla  |
         * =======================
         * |    W2,1   ||   W2,2 |
         * -----------------------
         * |    pla    ||    pla |
         * ======================= 
         * Could figure out the prealloc size... but I don't want to.
         * So I use cpp string (and inefficiently)
         * */
        std::string top_rows[N], bot_rows[N];
        std::string toptop_row;
        uint64_t max_row_width = 0;
        for (uint64_t i = 0; i < N; i++)
        {
            std::string top_row, bot_row;
            for (uint64_t j = 0; j < N; j++)
            {
                mac_t pla;//, ala;
                pla = down_latches[i][j];
                // ala = right_latches[i][j];
                std::string w_str, ala_str, pla_str;
                /* Quick and dirty */
                // ala_str = std::to_string(ala.value);
                ala_str = "";
                pla_str = std::to_string(pla.value);
                w_str = !enabled[i][j] ? "Disabled" : "W="+std::to_string(weights_sram[i][j].value);
                uint64_t wwidth = w_str.length();
                uint64_t bwidth = pla_str.length();
                uint64_t twidth = std::max(std::max(wwidth, bwidth), 8LLU) + 2;
                std::string pw_str = std::vformat("{:^"+std::to_string(twidth)+"}", std::make_format_args(w_str));
                std::string ppla_str = std::vformat("{:^"+std::to_string(twidth)+"}", std::make_format_args(pla_str));
                top_row += "| " + pw_str + " | " + ala_str + " ";
                bot_row += "| " + ppla_str + " |" + std::string(ala_str.length()+2, '-');
                if (i == 0)
                {
                    std::string toptop_str = std::to_string(top_values[j].value) + "↓";
                    std::string ptoptop_str = std::vformat("{:^"+std::to_string(twidth)+"}", std::make_format_args(toptop_str));
                    toptop_row += "  " + ptoptop_str + "   " + std::string(ala_str.length(), ' ') + " ";
                }
            }
            top_rows[i] = top_row;
            bot_rows[i] = bot_row;
            max_row_width = top_row.length() > max_row_width ? top_row.length() : max_row_width;
        }
        std::string ret;
        uint64_t max_l_width = 0;
        for (uint64_t i = 0; i < N; i++)
            max_l_width = std::max(max_l_width, (uint64_t)std::to_string(left_values[i].value).length());
        max_l_width += 5;
        std::string lsep = std::string(max_l_width, ' ');
        std::string sep = lsep+std::string(max_row_width+1, '=');
        ret += lsep+toptop_row + "\n" + sep + "\n";
        for (uint64_t i = 0; i < N; i++)
            ret += " " + std::to_string(left_values[i].value) + " -> " + top_rows[i] + "|\n" + \
                    lsep + bot_rows[i] + "|\n" + sep + "\n";
        return ret;
    }
    //void print_result_values()
    //{
    //    for (int i = 0; i < N; i++)
    //    {
    //        for (int j = 0; j < N; j++)
    //            std::cout << "| " << result[i][j].value << " ";
    //        std::cout << "|" << std::endl;
    //    }
    //}
};
#endif 
