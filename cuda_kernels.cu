/*********************************************
*   Project: Práctica de Computadores Avanzados 
*
*   Program name: cuda_kernels.cu
*
*   Author: Sergio Jiménez
*
*   Date created: 11-12-2020
*
*   Porpuse: Gestión para la realización de varios filtros y comparativas entre CUDA y OpenCV
*
*   Revision History: Reflejado en el repositorio de GitHub
|*********************************************/

#include <thread>
#include <chrono>
#include <string.h>
#include <time.h>
#include <iostream>
#include <math.h>
#include <typeinfo>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/highgui/highgui.hpp>
#include <opencv2/stitching.hpp>
#include <opencv2/core.hpp>
#include "include/colours.h"

#define N 25.0 // Number of threads
#define DIM_KERNEL 3 // Dimension of Sobel kernel

/*Global variables for the  sobel kernel's gradient*/
__device__ const int kernel_sobel_x[DIM_KERNEL][DIM_KERNEL]={{-1,0,1},{-2,0,2},{-1,0,1}};
__device__ const int kernel_sobel_y[DIM_KERNEL][DIM_KERNEL]={{-1,-2,-1},{0,0,0},{1,2,1}};

__device__ const int kernel_sharpen[DIM_KERNEL][DIM_KERNEL] = {{0,-1,0},{-1,5,-1},{0,-1,0}};

void sobelFilterOpenCV(cv::Mat scr_image, cv::Mat dest_image){
  cv::Mat grad_x, grad_y, abs_grad_x, abs_grad_y;
 
  cv::Sobel(scr_image, grad_x, CV_16S, 1, 0, 3, 1, 0, cv::BORDER_DEFAULT);// Gradient of X
  cv::convertScaleAbs(grad_x, abs_grad_x);
  
  cv::Sobel(scr_image, grad_y, CV_16S, 0, 1, 3, 1, 0, cv::BORDER_DEFAULT);// Gradient of Y
  cv::convertScaleAbs(grad_y, abs_grad_y);
  // Link all the gradients
  cv::addWeighted( abs_grad_x, 0.5, abs_grad_y, 0.5, 0, dest_image );
}

void sharpenKernelOpenCV(cv::Mat scr_image, cv::Mat dest_image){
  cv::GaussianBlur(scr_image, dest_image, cv::Size(0, 0), 3);
  cv::addWeighted(scr_image, 1.5, dest_image, -0.5, 0, dest_image);

}

__global__ void sobelKernelCUDA(unsigned char* src_image, unsigned char* dest_image, int width, int height){
     
    float dx,dy,result;

    int x = threadIdx.x + blockIdx.x * blockDim.x;
    int y = threadIdx.y + blockIdx.y * blockDim.y;
    
    dx = (kernel_sobel_x[0][0] * src_image[(x-1)*height + (y-1)]) + (kernel_sobel_x[0][1] * src_image[(x-1)*height + y]) + (kernel_sobel_x[0][2] * src_image[(x-1)*height+(y+1)]) +
    (kernel_sobel_x[1][0] * src_image[x*height+(y-1)]) + (kernel_sobel_x[1][1] * src_image[x*height+y]) +(kernel_sobel_x[1][2] * src_image[x*height+(y+1)]) + 
    (kernel_sobel_x[2][0] * src_image[(x+1)*height +(y-1)]) + (kernel_sobel_x[2][1] *src_image[(x+1)*height + y]) + (kernel_sobel_x[2][2] * src_image[(x+1)*height + (y+1)]);
    
    dy = (kernel_sobel_y[0][0] * src_image[(x-1)*height + (y-1)]) + (kernel_sobel_y[0][1] * src_image[(x-1)*height + y]) + (kernel_sobel_y[0][2] * src_image[(x-1)*height+(y+1)]) +
    (kernel_sobel_y[1][0] * src_image[x*height+(y-1)]) + (kernel_sobel_y[1][1] * src_image[x*height+y]) +(kernel_sobel_y[1][2] * src_image[x*height+(y+1)]) + 
    (kernel_sobel_y[2][0] * src_image[(x+1)*height +(y-1)]) + (kernel_sobel_y[2][1] *src_image[(x+1)*height + y]) + (kernel_sobel_y[2][2] * src_image[(x+1)*height + (y+1)]);
    
    result = sqrt((pow(dx,2))+ (pow(dy,2)));

    /*Noise suppression*/
    if (result > 255) result = 255;
    if (result < 0) result = 0;

    dest_image[x*height+y] = (int)result;

}

__global__ void sharpenKernelCUDA(unsigned char* src_image, unsigned char* dest_image, int width, int height){
   
  float result;

  int x = threadIdx.x + blockIdx.x * blockDim.x;
  int y = threadIdx.y + blockIdx.y * blockDim.y;
  
  result = (kernel_sharpen[0][0] * src_image[(x-1)*height + (y-1)]) + (kernel_sharpen[0][1] * src_image[(x-1)*height + y]) + (kernel_sharpen[0][2] * src_image[(x-1)*height+(y+1)]) +
  (kernel_sharpen[1][0] * src_image[x*height+(y-1)]) + (kernel_sharpen[1][1] * src_image[x*height+y]) +(kernel_sharpen[1][2] * src_image[x*height+(y+1)]) + 
  (kernel_sharpen[2][0] * src_image[(x+1)*height +(y-1)]) + (kernel_sharpen[2][1] *src_image[(x+1)*height + y]) + (kernel_sharpen[2][2] * src_image[(x+1)*height + (y+1)]);
  
  /*Noise suppression*/
  if (result > 255) result = 255;
  if (result < 0) result = 0;

  dest_image[x*height+y] = (int)result;

}


cudaError_t testCuErr(cudaError_t result){
  if (result != cudaSuccess) {
    printf(FCYN("[CUDA MANAGER] CUDA Runtime Error: %s\n"), cudaGetErrorString(result));
    assert(result == cudaSuccess);      
  }
  return result;
}

int main(int argc,char * argv[]){
    
    int rows, cols;
    cv::Mat src_image, dst_image;
    
    if (argc!=3){
        std::cout << FRED("[MANAGER] The number of arguments are incorrect, please insert <image> <filter name: sobel, sharpen>") << std::endl;
        return 1;
    }

    if (strcmp(argv[2], "") == 0){
      std::cout << FRED("[MANAGER] The <filter name: sobel, sharpen> is not indicated") << std::endl;
      return 1;
    }
    
    src_image = cv::imread(argv[1]);
    
    if (src_image.empty()){
        std::cout << FRED("[MANAGER] There is a problem reading the image ")<< src_image << std::endl;
        return 1;
    }

    cv::cvtColor(src_image, src_image, cv::COLOR_RGB2GRAY);
    dst_image = cv::Mat::zeros(src_image.size(), src_image.type());
    
    cols = src_image.cols;
    rows = src_image.rows;

    std::cout << FCYN("[MANAGER] Using Image ") << argv[1] << FCYN(" | ROWS = ") <<  rows << FCYN(" COLS = ") << cols << std::endl;
    sobelFilterOpenCV(src_image, dst_image);

    /*CUDA PART*/
    
    unsigned char *d_image, *h_image;
    int size = rows * cols;
    
    testCuErr(cudaMalloc((void**)&d_image, size));
    testCuErr(cudaMalloc((void**)&h_image, size));

    testCuErr(cudaMemcpy(d_image,src_image.data,size, cudaMemcpyHostToDevice));
    cudaMemset(h_image, 0, size);
    
    dim3 threadsPerBlock(N, N, 1);
    dim3 numBlocks((int)ceil(rows/N), (int)ceil(cols/N), 1);

    if (strcmp(argv[2], "sobel") == 0)  sobelKernelCUDA <<<numBlocks, threadsPerBlock>>> (d_image, h_image, rows, cols);
    if (strcmp(argv[2], "sharpen") == 0) sharpenKernelCUDA <<<numBlocks, threadsPerBlock>>> (d_image, h_image, rows, cols);


      testCuErr(cudaGetLastError());

    cudaMemcpy(src_image.data, h_image, size, cudaMemcpyDeviceToHost);
    cudaFree(d_image); 
    cudaFree(h_image);
    
    cv::imshow("OPENCV Filter", dst_image);
    cv::imshow("CUDA Filter",src_image);

    int k = cv::waitKey(0); // Wait for a keystroke in the windows

  
  return 0;
  }