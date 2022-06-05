// SPDX-License-Identifier: MIT
// Copyright (c) 2021  Kenji Koide (k.koide@aist.go.jp)

#pragma once

#include <vector>
#include <Eigen/Core>

#include <gtsam_ext/types/frame.hpp>
#include <gtsam_ext/types/frame_cpu.hpp>

// forward declaration
struct CUstream_st;

namespace gtsam_ext {

/**
 * @brief Point cloud frame on GPU memory
 */
struct FrameGPU : public FrameCPU {
public:
  using Ptr = std::shared_ptr<FrameGPU>;
  using ConstPtr = std::shared_ptr<const FrameGPU>;

  template <typename T, int D>
  FrameGPU(const Eigen::Matrix<T, D, 1>* points, int num_points);

  template <typename T, int D, typename Alloc>
  FrameGPU(const std::vector<Eigen::Matrix<T, D, 1>, Alloc>& points) : FrameGPU(points.data(), points.size()) {}

  FrameGPU(const Frame& frame);

  FrameGPU();
  ~FrameGPU();

  // add_*_gpu() only adds attributes to GPU storage
  template <typename T>
  void add_times(const T* times, int num_points, CUstream_st* stream = 0) {
    FrameCPU::add_times<T>(times, num_points);
    add_times_gpu(times, num_points, stream);
  }
  template <typename T>
  void add_times(const std::vector<T>& times, CUstream_st* stream = 0) {
    add_times(times.data(), times.size(), stream);
  }

  template <typename T>
  void add_times_gpu(const T* times, int num_points, CUstream_st* stream = 0);
  template <typename T>
  void add_times_gpu(const std::vector<T>& times, CUstream_st* stream = 0) {
    add_times_gpu(times.data(), times.size(), stream);
  }

  template <typename T, int D>
  void add_points(const Eigen::Matrix<T, D, 1>* points, int num_points, CUstream_st* stream = 0) {
    FrameCPU::add_points<T, D>(points, num_points);
    add_points_gpu(points, num_points, stream);
  }
  template <typename T, int D, typename Alloc>
  void add_points(const std::vector<Eigen::Matrix<T, D, 1>, Alloc>& points, CUstream_st* stream = 0) {
    add_points(points.data(), points.size(), stream);
  }

  template <typename T, int D>
  void add_points_gpu(const Eigen::Matrix<T, D, 1>* points, int num_points, CUstream_st* stream = 0);
  template <typename T, int D, typename Alloc>
  void add_points_gpu(const std::vector<Eigen::Matrix<T, D, 1>, Alloc>& points, CUstream_st* stream = 0) {
    add_points_gpu(points.data(), points.size(), stream);
  }

  template <typename T, int D>
  void add_normals(const Eigen::Matrix<T, D, 1>* normals, int num_points, CUstream_st* stream = 0) {
    FrameCPU::add_normals<T, D>(normals, num_points);
    add_normals_gpu<T, D>(normals, num_points, stream);
  }
  template <typename T, int D, typename Alloc>
  void add_normals(const std::vector<Eigen::Matrix<T, D, 1>, Alloc>& normals, CUstream_st* stream = 0) {
    add_normals(normals.data(), normals.size(), stream);
  }

  template <typename T, int D>
  void add_normals_gpu(const Eigen::Matrix<T, D, 1>* normals, int num_points, CUstream_st* stream = 0);
  template <typename T, int D, typename Alloc>
  void add_normals_gpu(const std::vector<Eigen::Matrix<T, D, 1>, Alloc>& normals, CUstream_st* stream = 0) {
    add_normals_gpu(normals.data(), normals.size(), stream);
  }

  template <typename T, int D>
  void add_covs(const Eigen::Matrix<T, D, D>* covs, int num_points, CUstream_st* stream = 0) {
    FrameCPU::add_covs<T, D>(covs, num_points);
    add_covs_gpu<T, D>(covs, num_points, stream);
  }
  template <typename T, int D, typename Alloc>
  void add_covs(const std::vector<Eigen::Matrix<T, D, D>, Alloc>& covs, CUstream_st* stream = 0) {
    add_covs(covs.data(), covs.size(), stream);
  }

  template <typename T, int D>
  void add_covs_gpu(const Eigen::Matrix<T, D, D>* covs, int num_points, CUstream_st* stream = 0);
  template <typename T, int D, typename Alloc>
  void add_covs_gpu(const std::vector<Eigen::Matrix<T, D, D>, Alloc>& covs, CUstream_st* stream = 0) {
    add_covs_gpu(covs.data(), covs.size(), stream);
  }

  template <typename T>
  void add_intensities(const T* intensities, int num_points, CUstream_st* stream = 0) {
    FrameCPU::add_intensities<T>(intensities, num_points);
    add_intensities_gpu(intensities, num_points, stream);
  }
  template <typename T>
  void add_intensities(const std::vector<T>& intensities, CUstream_st* stream = 0) {
    add_intensities(intensities.data(), intensities.size(), stream);
  }

  template <typename T>
  void add_intensities_gpu(const T* intensities, int num_points, CUstream_st* stream = 0);
  template <typename T>
  void add_intensities_gpu(const std::vector<T>& intensities, CUstream_st* stream = 0) {
    add_intensities_gpu(intensities.data(), intensities.size(), stream);
  }

  // copy data from GPU to CPU
  std::vector<Eigen::Vector3f, Eigen::aligned_allocator<Eigen::Vector3f>> get_points_gpu() const;
  std::vector<Eigen::Matrix3f, Eigen::aligned_allocator<Eigen::Matrix3f>> get_covs_gpu() const;
};

}  // namespace gtsam_ext
