#include <fstream>
#include <iostream>
#include <vector>

struct PonyAnalyzer
{
	struct message_t {
		size_t start_index, timing_cfg;
		float base_width;
	};

	std::vector<message_t> messages;
	std::vector<float> samples;
	std::vector<int> pulses;
	std::vector<std::vector<float>> timing_configs;
	float max_sample, min_sample, trigger;

	void read_samples(const char *filename)
	{
		std::ifstream f;
		f.open(filename);
		if (f.fail()) {
			std::cerr << "Can't open input file '" << filename << "'!" << std::endl;
			exit(1);
		}

		float sample;
		while (f >> sample) {
			if (samples.empty()) {
				max_sample = sample;
				min_sample = sample;
			} else {
				max_sample = std::max(sample, max_sample);
				min_sample = std::min(sample, min_sample);
			}
			samples.push_back(sample);
			trigger = (max_sample + min_sample) * 0.5;
		}
	}

	void extract_pulses()
	{
		pulses.clear();
		pulses.push_back(0);

		for (float sample : samples) {
			if (sample < trigger) {
				if (pulses.size() % 2 == 0)
					pulses.push_back(0);
			} else {
				if (pulses.size() % 2 == 1)
					pulses.push_back(0);
			}
			pulses.back()++;
		}
	}

	bool about_equal(float a, float b)
	{
		if (a*0.9 > b) return false;
		if (a < b*0.9) return false;
		return true;
	}

	void find_messages()
	{
		std::vector<int> init_sequence = {0, 0, 0, 0, 2, 4, 2, 0, 0, 0, 0, 0, 1, 0, 0};

		for (size_t i = 0, pos = 0; i+20 < pulses.size(); pos += pulses[i], i++)
		for (size_t k = 0; k < timing_configs.size(); k++)
		{
			float base_width = ((pulses[i] + pulses[i+1] + pulses[i+2] + pulses[i+3]) / 4.0) / timing_configs[k][0];
			for (size_t n = 0; n < init_sequence.size(); n++)
				if (!about_equal(timing_configs[k][init_sequence[n]]*base_width, pulses[i+n]))
					goto next_sample;

			std::cout << "Message #" << messages.size() << ": Start at sample " << pos << " (pulse " << i <<
					") with timing profile " << k << " and base width " << base_width << "." << std::endl;

			message_t msg;
			msg.start_index = i;
			msg.timing_cfg = k;
			msg.base_width = base_width;
			messages.push_back(msg);
		next_sample:;
		}
	}

	std::string decode_8b10b(uint32_t symbol)
	{
		std::string symbol_name;
		int val_upper = -1, val_lower = -1;

		bool a = (symbol & (1 << 9)) != 0;
		bool b = (symbol & (1 << 8)) != 0;
		bool c = (symbol & (1 << 7)) != 0;
		bool d = (symbol & (1 << 6)) != 0;
		bool e = (symbol & (1 << 5)) != 0;
		bool i = (symbol & (1 << 4)) != 0;
		bool f = (symbol & (1 << 3)) != 0;
		bool g = (symbol & (1 << 2)) != 0;
		bool h = (symbol & (1 << 1)) != 0;
		bool j = (symbol & (1 << 0)) != 0;

		std::string abcdei = std::string(a ? "1" : "0") + std::string(b ? "1" : "0") + std::string(c ? "1" : "0") +
				std::string(d ? "1" : "0") + std::string(e ? "1" : "0") + std::string(i ? "1" : "0");

		std::string fghj = std::string(f ? "1" : "0") + std::string(g ? "1" : "0") + std::string(h ? "1" : "0") + std::string(j ? "1" : "0");

		if (abcdei == "100111" || abcdei == "011000") symbol_name = "D.00", val_lower =  0;
		if (abcdei == "011101" || abcdei == "100010") symbol_name = "D.01", val_lower =  1;
		if (abcdei == "101101" || abcdei == "010010") symbol_name = "D.02", val_lower =  2;
		if (abcdei == "110001"                      ) symbol_name = "D.03", val_lower =  3;
		if (abcdei == "110101" || abcdei == "001010") symbol_name = "D.04", val_lower =  4;
		if (abcdei == "101001"                      ) symbol_name = "D.05", val_lower =  5;
		if (abcdei == "011001"                      ) symbol_name = "D.06", val_lower =  6;
		if (abcdei == "111000" || abcdei == "000111") symbol_name = "D.07", val_lower =  7;
		if (abcdei == "111001" || abcdei == "000110") symbol_name = "D.08", val_lower =  8;
		if (abcdei == "100101"                      ) symbol_name = "D.09", val_lower =  9;
		if (abcdei == "010101"                      ) symbol_name = "D.10", val_lower = 10;
		if (abcdei == "110100"                      ) symbol_name = "D.11", val_lower = 11;
		if (abcdei == "001101"                      ) symbol_name = "D.12", val_lower = 12;
		if (abcdei == "101100"                      ) symbol_name = "D.13", val_lower = 13;
		if (abcdei == "011100"                      ) symbol_name = "D.14", val_lower = 14;
		if (abcdei == "010111" || abcdei == "101000") symbol_name = "D.15", val_lower = 15;
		if (abcdei == "011011" || abcdei == "100100") symbol_name = "D.16", val_lower = 16;
		if (abcdei == "100011"                      ) symbol_name = "D.17", val_lower = 17;
		if (abcdei == "010011"                      ) symbol_name = "D.18", val_lower = 18;
		if (abcdei == "110010"                      ) symbol_name = "D.19", val_lower = 19;
		if (abcdei == "001011"                      ) symbol_name = "D.20", val_lower = 20;
		if (abcdei == "101010"                      ) symbol_name = "D.21", val_lower = 21;
		if (abcdei == "011010"                      ) symbol_name = "D.22", val_lower = 22;
		if (abcdei == "111010" || abcdei == "000101") symbol_name = "D.23", val_lower = 23;
		if (abcdei == "110011" || abcdei == "001100") symbol_name = "D.24", val_lower = 24;
		if (abcdei == "100110"                      ) symbol_name = "D.25", val_lower = 25;
		if (abcdei == "010110"                      ) symbol_name = "D.26", val_lower = 26;
		if (abcdei == "110110" || abcdei == "001001") symbol_name = "D.27", val_lower = 27;
		if (abcdei == "001110"                      ) symbol_name = "D.28", val_lower = 28;
		if (abcdei == "001111" || abcdei == "110000") symbol_name = "K.28", val_lower = 28;
		if (abcdei == "101110" || abcdei == "010001") symbol_name = "D.29", val_lower = 29;
		if (abcdei == "011110" || abcdei == "100001") symbol_name = "D.30", val_lower = 30;
		if (abcdei == "101011" || abcdei == "010100") symbol_name = "D.31", val_lower = 31;

		if (symbol_name[0] == 'D') {
			if (fghj == "1011" || fghj == "0100") symbol_name += ".0 ", val_upper = 0;
			if (fghj == "1001"                  ) symbol_name += ".1 ", val_upper = 1;
			if (fghj == "0101"                  ) symbol_name += ".2 ", val_upper = 2;
			if (fghj == "1100" || fghj == "0011") symbol_name += ".3 ", val_upper = 3;
			if (fghj == "1101" || fghj == "0010") symbol_name += ".4 ", val_upper = 4;
			if (fghj == "1010"                  ) symbol_name += ".5 ", val_upper = 5;
			if (fghj == "0110"                  ) symbol_name += ".6 ", val_upper = 6;
			if (fghj == "1110" || fghj == "0001") symbol_name += ".P7", val_upper = 7;
			if (fghj == "0111" || fghj == "1000") symbol_name += ".A7", val_upper = 7;
		}

		if (symbol_name[0] == 'K') {
			if (fghj == "1011" || fghj == "0100") symbol_name += ".0 ", val_upper = 0 + 8;
			if (fghj == "0110" || fghj == "1001") symbol_name += ".1 ", val_upper = 1 + 8;
			if (fghj == "1010" || fghj == "0101") symbol_name += ".2 ", val_upper = 2 + 8;
			if (fghj == "1100" || fghj == "0011") symbol_name += ".3 ", val_upper = 3 + 8;
			if (fghj == "1101" || fghj == "0010") symbol_name += ".4 ", val_upper = 4 + 8;
			if (fghj == "0101" || fghj == "1010") symbol_name += ".5 ", val_upper = 5 + 8;
			if (fghj == "1001" || fghj == "0110") symbol_name += ".6 ", val_upper = 6 + 8;
			if (fghj == "0111" || fghj == "1000") symbol_name += ".7 ", val_upper = 7 + 8;
		}

		if (symbol_name == "K.28.2 .5 ") {
			if (abcdei+fghj == "0011110101" || abcdei+fghj == "1100001010") symbol_name = "K.28.2 ", val_upper = 2 + 8;
			if (abcdei+fghj == "0011111010" || abcdei+fghj == "1100000101") symbol_name = "K.28.5 ", val_upper = 5 + 8;
		}

		int value = (val_upper << 5) | val_lower;
		char buffer[100];

		snprintf(buffer, 100, " %3d %3x", value, value);
		symbol_name += buffer;

		return symbol_name;
	}

	void decode_messages()
	{
		size_t message_idx = 0;
		std::vector<float> tmconfig;
		float base_width;
		bool active = false;
		bool waiting = false;

		uint32_t buffer;
		int buffer_n = 0;

		for (size_t i = 0; i < pulses.size(); i++)
		{
			if (message_idx < messages.size() && i == messages[message_idx].start_index) {
				std::cout << "Message #" << message_idx << ":" << std::endl <<
						"  Using timing profile " << messages[message_idx].timing_cfg <<
						" and base width " << messages[message_idx].base_width << "." << std::endl;
				tmconfig = timing_configs[messages[message_idx].timing_cfg];
				base_width = messages[message_idx].base_width;
				message_idx++;
				waiting = true;
				continue;
			}

			if (!active && !waiting)
				continue;

			for (size_t k = 0; k < tmconfig.size(); k++)
				if (about_equal(tmconfig[k] * base_width, pulses[i])) {
					for (int l = 0; l < k+1; l++) {
						buffer = buffer << 1 | (i % 2);
						buffer_n++;
					}
					goto matched_pulse;
				}

			std::cout << "  END-OF-MESSAGE" << std::endl;
			active = false;
			waiting = false;
			continue;

		matched_pulse:;
			if (waiting && buffer_n >= 10 && (buffer & 0x7f) == 0x1f) {
				active = true;
				waiting = false;
				buffer_n = 7;
			}

			if (active && buffer_n >= 10) {
				std::cout << "  ";
				uint32_t symbol = 0;
				for (int k = 0; k < 10; k++) {
					int bit = (buffer >> --buffer_n) & 1;
					std::cout << (bit ? '1' : '0');
					symbol = (symbol << 1) | bit;
				}
				std::cout << " " << decode_8b10b(symbol) << std::endl;
			}
		}
	}
};

int main()
{
	PonyAnalyzer pa;
	pa.read_samples("waveform.txt");

	std::cout << "Read " << pa.samples.size() << " samples from waveform.txt." << std::endl;
	std::cout << "Sample range: " << pa.min_sample << " .. " << pa.max_sample << std::endl;
	std::cout << "Trigger level: " << pa.trigger << std::endl;

	pa.extract_pulses();
	std::cout << "Extracted " << pa.pulses.size() << " pulses." << std::endl;
#if 0
	for (size_t i = 0, pos = 0; i < pa.pulses.size(); pos += pa.pulses[i], i++)
		std::cout << "   " << pos << " [" << i << "]: " << pa.pulses[i] << std::endl;
#endif

	// Configure timing profiles
	pa.timing_configs.push_back(std::vector<float>({1, 2, 3, 4, 5}));

	pa.find_messages();
	pa.decode_messages();

	return 0;
}

