#include "random_utf8.hpp"

#include <chrono>
#include <iomanip>
#include <iostream>
#include <span>
#include <vector>

#include <cstddef>

bool has_leading_zero(const std::byte& byte)
{
	return (byte & std::byte{0b10000000})==std::byte{0b00000000};
}

bool is_continuation(const std::byte& byte)
{
	return (byte & std::byte{0b11000000})==std::byte{0b10000000};
}

bool is_overlong(const std::byte& byte)
{
	return (byte & std::byte{0b11111000})==std::byte{0b11111000};
}

bool is_empty_header(const std::byte& byte)
{
	return byte==std::byte{0b11000000} || byte==std::byte{0b11100000} || byte==std::byte{0b11110000};
}

bool is_too_large(const std::byte& byte)
{
	if((byte & std::byte{0b11111100})==std::byte{0b11110100})
		if(byte!=std::byte{0b11110100})
			return true;

	return false;
}

bool valid_utf8(std::span<const std::byte> data)
{
	for(std::size_t i=0; i<data.size(); ++i)
	{
		const auto& current = data[i];
		
		if(has_leading_zero(current))
			continue;
		if(is_continuation(current))
			return false;
		if(is_overlong(current))
			return false;
		if(is_empty_header(current))
			return false;
		if(is_too_large(current))
			return false;
		

		unsigned expected_continuation_bytes = 1;
		if((current & std::byte{0b11100000})==std::byte{0b11100000})
			++expected_continuation_bytes;
		
		if((current & std::byte{0b11110000})==std::byte{0b11110000})
			++expected_continuation_bytes;

		if(i+expected_continuation_bytes >= data.size())
			return false;
		
		for(unsigned following_byte_number=1; following_byte_number<=expected_continuation_bytes; ++following_byte_number)
			if(const auto following_byte = data[i+following_byte_number] & std::byte{0b11111111}; !is_continuation(following_byte))
				return false;

		i += expected_continuation_bytes;
	}
	return true;
}

int main()
{
	constexpr std::size_t length = 100000000;
	[[maybe_unused]] const std::size_t number_of_errors = length*0.01;
	 
	random_file_creator input_creator;
	
	std::chrono::duration<double> total_elapsed_seconds_correct{};
	std::chrono::duration<double> total_elapsed_seconds_incorrect{};
	std::size_t correct_tests = 0;
	
	constexpr std::size_t number_of_tests = 5;
	for(std::size_t i=0; i<number_of_tests; ++i)
	{
		const auto test_correct = input_creator.create_correct_text(length);
		const auto test_incorrect = input_creator.create_incorrect_text(length, number_of_errors);
		
		const auto start_correct = std::chrono::steady_clock::now();
			const auto test_correct_result = valid_utf8(test_correct);
		const auto end_correct = std::chrono::steady_clock::now();
		const std::chrono::duration<double> elapsed_seconds_correct = end_correct - start_correct;
		
		const auto start_incorrect = std::chrono::steady_clock::now();
			const auto test_incorrect_result = valid_utf8(test_incorrect);
		const auto end_incorrect = std::chrono::steady_clock::now();
		const std::chrono::duration<double> elapsed_seconds_incorrect = end_incorrect - start_incorrect;
		
		total_elapsed_seconds_correct += elapsed_seconds_correct;
		total_elapsed_seconds_incorrect += elapsed_seconds_incorrect;
		if(const auto expected = true; test_correct_result==expected)
			++correct_tests;
		if(const auto expected = false; test_incorrect_result==expected)
			++correct_tests;
	}
	
	std::cout << "Number of tests: " << number_of_tests << '\n' << "Test file length in Byte: " << length << '\n';
	std::cout << "Elapsed time 1: " << total_elapsed_seconds_correct.count() << "s\n";
	std::cout << "Elapsed time 2: " << total_elapsed_seconds_incorrect.count() << "s\n";
	const auto all_tests_correct = correct_tests==number_of_tests*2 ? true : false;
	std::cout << "All tests where correct:  " << std::boolalpha << all_tests_correct << '\n';
}
