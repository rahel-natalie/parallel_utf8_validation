#include "random_utf8.hpp"

#include <chrono>
#include <iomanip>
#include <iostream>
#include <span>
#include <vector>

#include <cstddef>

#define CHECK_CUDA(call)                                       	\
{																\
    if((call)!=cudaSuccess)                                  	\
    {                                                           \
        std::cerr << "CUDA error at " << __LINE__ << '\n'; 		\
        exit(EXIT_FAILURE);                                     \
    }															\
}

__device__ bool has_leading_zero(unsigned char byte)
{
	return (byte & 0b10000000)==0b00000000;
}

__device__ bool is_continuation(unsigned char byte)
{
	return (byte & 0b11000000)==0b10000000;
}

__device__ bool is_overlong(unsigned char byte)
{
	return (byte & 0b11111000)==0b11111000;
}

__device__ bool is_empty_header(unsigned char byte)
{
	return byte==0b11000000 || byte==0b11100000 || byte==0b11110000;
}

__device__ bool is_too_large(unsigned char byte)
{
	return byte>0b11110100 && byte<0b11111000;
}

__global__ void validate_utf8(unsigned char* data, size_t size, bool* result)
{
    extern __shared__ unsigned char shared_data[]; 

    constexpr uint32_t elements_per_thread = 16;
    const uint32_t block_size = blockDim.x * elements_per_thread;
    const size_t block_start_idx = (size_t) blockIdx.x * block_size;

    const size_t global_index = block_start_idx + threadIdx.x * elements_per_thread;
	if(global_index+elements_per_thread<=size)
		 reinterpret_cast<uint4*>(&shared_data[threadIdx.x * elements_per_thread])[0] = reinterpret_cast<const uint4*>(&data[global_index])[0];
    else
    {
        for(int i=0; i<elements_per_thread; ++i)
            if(global_index+i<size) 
                shared_data[threadIdx.x * elements_per_thread + i] = data[global_index + i];
    }

    if(threadIdx.x < 3)
        if(const size_t halo_idx = block_start_idx + block_size + threadIdx.x; halo_idx < size)
			shared_data[block_size + threadIdx.x] = data[halo_idx];

    __syncthreads();


    for(uint32_t i=0; i<elements_per_thread; ++i)
    {
        const uint32_t local_idx = threadIdx.x + (i * blockDim.x); 
        size_t current_global_idx = block_start_idx + local_idx;

        if(current_global_idx>=size) break;

        const unsigned char byte = shared_data[local_idx];

        if(has_leading_zero(byte))
			continue;
        if(is_continuation(byte))
        {
            if(current_global_idx==0)
            {
				*result = false;
				return;
			}
			
            unsigned char previous = (local_idx > 0) ? shared_data[local_idx - 1] : data[current_global_idx - 1];
            if(has_leading_zero(previous))
            {
				*result = false;
				return;
			}
        }
        if(is_overlong(byte) || is_empty_header(byte) || is_too_large(byte))
        {
            *result = false;
            return;
        }

        unsigned expected_continuation_bytes = 0;
        if((byte & 0b11100000) == 0b11000000) expected_continuation_bytes = 1;
		if((byte & 0b11110000) == 0b11100000) expected_continuation_bytes = 2;
        if((byte & 0b11111000) == 0b11110000) expected_continuation_bytes = 3;

        if(current_global_idx+expected_continuation_bytes>=size)
        {
            *result = false;
            return;
        }

        for(unsigned following_byte_number=1; following_byte_number<=expected_continuation_bytes; ++following_byte_number)
        {
            if(const unsigned char following_byte = shared_data[local_idx + following_byte_number]; !is_continuation(following_byte))
            {
                *result = false;
                return;
            }
        }
    }
}


int main()
{
	constexpr std::size_t length = 100000000;
	[[maybe_unused]] constexpr std::size_t number_of_errors = length*0.01;
	 
	random_file_creator input_creator;
	
	std::chrono::duration<double> total_elapsed_seconds_correct{};
	std::chrono::duration<double> total_elapsed_seconds_incorrect{};
	std::size_t correct_tests = 0;
	
	constexpr std::size_t number_of_tests = 5;
	for(std::size_t i=0; i<number_of_tests; ++i)
	{
		bool result_test_correct{};
		bool result_test_incorrect{};
		
		bool* result_device = nullptr;
		constexpr bool set_result = true;
		CHECK_CUDA(cudaMalloc(&result_device, sizeof(bool)));
		
		const auto test_correct_host = input_creator.create_correct_text(length);
		const auto test_incorrect_host = input_creator.create_incorrect_text(length, number_of_errors);
		
		unsigned char* test_correct_device = nullptr;
		unsigned char* test_incorrect_device = nullptr;
		
		const size_t length_in_bytes = (size_t) length * sizeof(unsigned char);
		CHECK_CUDA(cudaMalloc(&test_correct_device, length_in_bytes));
		CHECK_CUDA(cudaMalloc(&test_incorrect_device, length_in_bytes));

		
		CHECK_CUDA(cudaMemcpy(test_correct_device, test_correct_host.data(), length_in_bytes, cudaMemcpyHostToDevice));
		CHECK_CUDA(cudaMemcpy(test_incorrect_device, test_incorrect_host.data(), length_in_bytes, cudaMemcpyHostToDevice));
		
		constexpr auto threads_per_block = 256;
		constexpr auto elements_per_thread = 16;
		constexpr auto halo_with_padding = 16;
		constexpr auto block_size = threads_per_block * elements_per_thread;
		constexpr size_t shared_memory_size = (block_size + halo_with_padding) * sizeof(unsigned char);
		constexpr size_t number_of_blocks = (length + block_size - 1) / block_size;
		
		CHECK_CUDA(cudaMemcpy(result_device, &set_result, sizeof(bool), cudaMemcpyHostToDevice));		
		const auto start_correct = std::chrono::steady_clock::now();
			validate_utf8<<<number_of_blocks, threads_per_block, shared_memory_size>>>(test_correct_device, length, result_device);
			cudaDeviceSynchronize();
		const auto end_correct = std::chrono::steady_clock::now();
		const std::chrono::duration<double> elapsed_seconds_correct = end_correct - start_correct;
		CHECK_CUDA(cudaMemcpy(&result_test_correct, result_device, sizeof(bool), cudaMemcpyDeviceToHost));
		
		CHECK_CUDA(cudaMemcpy(result_device, &set_result, sizeof(bool), cudaMemcpyHostToDevice));		
		const auto start_incorrect = std::chrono::steady_clock::now();
			validate_utf8<<<number_of_blocks, threads_per_block, shared_memory_size>>>(test_incorrect_device, length, result_device);
			cudaDeviceSynchronize();
		const auto end_incorrect = std::chrono::steady_clock::now();
		const std::chrono::duration<double> elapsed_seconds_incorrect = end_incorrect - start_incorrect;
		CHECK_CUDA(cudaMemcpy(&result_test_incorrect, result_device, sizeof(bool), cudaMemcpyDeviceToHost));
		
		total_elapsed_seconds_correct += elapsed_seconds_correct;
		total_elapsed_seconds_incorrect += elapsed_seconds_incorrect;
		
		if(constexpr auto expected = true; result_test_correct==expected)
			++correct_tests;
		if(constexpr auto expected = false; result_test_incorrect==expected)
			++correct_tests;
		
			
		cudaFree(result_device);
		cudaFree(test_correct_device);
		cudaFree(test_incorrect_device);
	}
	
	std::cout << "Number of tests: " << number_of_tests << '\n' << "Test file length in Byte: " << length << '\n';
	std::cout << "Elapsed time 1: " << total_elapsed_seconds_correct.count() << "s\n";
	std::cout << "Elapsed time 2: " << total_elapsed_seconds_incorrect.count() << "s\n";
	const auto all_tests_correct = correct_tests==number_of_tests*2 ? true : false;
	std::cout << "All tests where correct:  " << std::boolalpha << all_tests_correct << '\n';
}
