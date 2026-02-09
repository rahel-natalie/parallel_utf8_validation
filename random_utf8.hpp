#ifndef JSON_RANDOM_UTF8_HPP
#define JSON_RANDOM_UTF8_HPP

#include <fstream>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

#include <cstddef>


class random_file_creator
{
	public:
	std::vector<std::byte> create_random_text(std::size_t length)
	{
		std::vector<std::byte> result{};
		result.reserve(length);
		for(std::size_t i=0; i<length; ++i)
			result.push_back(random_byte());
		return result;
	}
	
	std::vector<std::byte> create_correct_text(std::size_t length)
	{
		std::uniform_int_distribution<int> distribution{1, 4};
		
		std::vector<std::byte> result{};
		result.reserve(length);
		for(std::size_t i=0; i<length; ++i)
		{
			switch(distribution(random_generator_))
			{
				case 1: result.push_back(leading_0_byte()); break;
				case 2:
				{
					if(i+1>=result.size()) continue;
					result.push_back(leading_11_byte());
					result.push_back(leading_10_byte());
					++i;
					break;
				}
				case 3:
				{
					if(i+2>=result.size()) continue;
					result.push_back(leading_111_byte());
					result.push_back(leading_10_byte());
					result.push_back(leading_10_byte());
					i+=2;
					break;
				}
				case 4:
				{
					if(i+3>=result.size()) continue;
					result.push_back(leading_1111_byte());
					result.push_back(leading_10_byte());
					result.push_back(leading_10_byte());
					result.push_back(leading_10_byte());
					i+=3;
					break;
				}
			}
		}
		return result;
	}
	
	std::vector<std::byte> create_incorrect_text(std::size_t length, std::size_t number_of_errors)
	{
		if(number_of_errors>length)
			throw std::runtime_error("number of errors must be less then text length");
			
		auto result = create_correct_text(length);
		unsigned errors_produced = 0;
		for(std::size_t i=result.size()-1; i>1 && errors_produced<number_of_errors; --i)
		{
			if((result[i] & std::byte{0b11000000})==std::byte{0b10000000})
			{
				result[i] = result[i] & std::byte{0b01111111};
				++errors_produced;
			}
			else if((result[i] & std::byte{0b10000000})==std::byte{0b00000000})
			{
				result[i] = result[i] | std::byte{0b10000000};
				++errors_produced;
			}
		}
		
		if(errors_produced<number_of_errors)
			throw std::runtime_error("could not produce that many errors");
			
		return result;
	}
	
	private:
	std::byte random_byte()
	{
		return std::byte(distribution_(random_generator_));
	}
	
	std::byte leading_0_byte()
	{
		return std::byte{0b01111111} & random_byte();
	}
	
	std::byte leading_10_byte()
	{
		return (std::byte{0b10000000} | random_byte()) & std::byte{0b10111111};
	}
	
	std::byte leading_11_byte()
	{
		return std::byte{0b11000000} | random_byte();
	};
	
	std::byte leading_111_byte()
	{
		return std::byte{0b11100000} | random_byte();
	};
	
	std::byte leading_1111_byte()
	{
		return std::byte{0b11110000} | random_byte();
	};
	
	std::random_device seed_;
	std::mt19937 random_generator_{seed_()};

	std::uniform_int_distribution<int> distribution_{0, 255};
};

#endif
