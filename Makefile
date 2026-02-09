all: run_cpu run_gpu

utf8_vali_cu: utf8_validation.cu
	nvcc -Werror all-warnings -std=c++20 -O2 -o utf8_vali_cu utf8_validation.cu

utf8_vali: utf8_validation.cpp
	g++ utf8_validation.cpp -o utf8_vali -Wall -pedantic -Werror -std=c++23 -O3

run_cpu: utf8_vali
	./utf8_vali

run_gpu: utf8_vali_cu
	./utf8_vali_cu

clean:
	rm utf8_vali utf8_vali_cu

.PHONY: all clean run_cpu run_gpu
