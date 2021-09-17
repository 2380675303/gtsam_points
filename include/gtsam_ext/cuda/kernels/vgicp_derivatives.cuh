#pragma once

#include <Eigen/Core>
#include <thrust/device_vector.h>

#include <gtsam_ext/cuda/kernels/pose.cuh>
#include <gtsam_ext/cuda/kernels/linearized_system.cuh>
#include <gtsam_ext/types/gaussian_voxelmap_gpu.hpp>

namespace gtsam_ext {

struct vgicp_derivatives_kernel {
  vgicp_derivatives_kernel(
    const thrust::device_ptr<const Eigen::Isometry3f>& linearization_point_ptr,
    const GaussianVoxelMapGPU& voxelmap,
    const thrust::device_ptr<const Eigen::Vector3f>& source_means,
    const thrust::device_ptr<const Eigen::Matrix3f>& source_covs)
  : linearization_point_ptr(linearization_point_ptr),
    voxel_num_points_ptr(voxelmap.num_points.data()),
    voxel_means_ptr(voxelmap.voxel_means.data()),
    voxel_covs_ptr(voxelmap.voxel_covs.data()),
    source_means_ptr(source_means),
    source_covs_ptr(source_covs) {}

  __device__ LinearizedSystem6 operator()(const thrust::pair<int, int>& source_target_correspondence) const {
    const int source_idx = source_target_correspondence.first;
    const int target_idx = source_target_correspondence.second;
    if (source_idx < 0 || target_idx < 0) {
      return LinearizedSystem6::zero();
    }

    const Eigen::Isometry3f& x = *thrust::raw_pointer_cast(linearization_point_ptr);
    const Eigen::Matrix3f R = x.linear();
    const Eigen::Vector3f t = x.translation();

    const Eigen::Vector3f& mean_A = thrust::raw_pointer_cast(source_means_ptr)[source_idx];
    const Eigen::Matrix3f& cov_A = thrust::raw_pointer_cast(source_covs_ptr)[source_idx];
    const Eigen::Vector3f transed_mean_A = R * mean_A + t;

    const Eigen::Vector3f& mean_B = thrust::raw_pointer_cast(voxel_means_ptr)[target_idx];
    const Eigen::Matrix3f& cov_B = thrust::raw_pointer_cast(voxel_covs_ptr)[target_idx];

    const int num_points = thrust::raw_pointer_cast(voxel_num_points_ptr)[target_idx];

    const Eigen::Matrix3f RCR = (R * cov_A * R.transpose());
    const Eigen::Matrix3f RCR_inv = (cov_B + RCR).inverse();
    Eigen::Vector3f error = mean_B - transed_mean_A;

    Eigen::Matrix<float, 3, 6> J_target;
    J_target.block<3, 3>(0, 0) = -skew_symmetric(transed_mean_A);
    J_target.block<3, 3>(0, 3) = Eigen::Matrix3f::Identity();

    Eigen::Matrix<float, 3, 6> J_source;
    J_source.block<3, 3>(0, 0) = R * skew_symmetric(mean_A);
    J_source.block<3, 3>(0, 3) = -R;

    LinearizedSystem6 linearized;
    linearized.error = 0.5f * error.transpose() * RCR_inv * error;
    linearized.H_target = J_target.transpose() * RCR_inv * J_target;
    linearized.H_source = J_source.transpose() * RCR_inv * J_source;
    linearized.H_target_source = J_target.transpose() * RCR_inv * J_source;
    linearized.b_target = J_target.transpose() * RCR_inv * error;
    linearized.b_source = J_source.transpose() * RCR_inv * error;

    return linearized;
  }

  thrust::device_ptr<const Eigen::Isometry3f> linearization_point_ptr;

  thrust::device_ptr<const int> voxel_num_points_ptr;
  thrust::device_ptr<const Eigen::Vector3f> voxel_means_ptr;
  thrust::device_ptr<const Eigen::Matrix3f> voxel_covs_ptr;

  thrust::device_ptr<const Eigen::Vector3f> source_means_ptr;
  thrust::device_ptr<const Eigen::Matrix3f> source_covs_ptr;
};

struct vgicp_error_kernel {
  vgicp_error_kernel(
    const thrust::device_ptr<const Eigen::Isometry3f>& linearization_point_ptr,
    const thrust::device_ptr<const Eigen::Isometry3f>& evaluation_point_ptr,
    const GaussianVoxelMapGPU& voxelmap,
    const thrust::device_ptr<const Eigen::Vector3f>& source_means,
    const thrust::device_ptr<const Eigen::Matrix3f>& source_covs)
  : linearization_point_ptr(linearization_point_ptr),
    evaluation_point_ptr(evaluation_point_ptr),
    voxel_num_points_ptr(voxelmap.num_points.data()),
    voxel_means_ptr(voxelmap.voxel_means.data()),
    voxel_covs_ptr(voxelmap.voxel_covs.data()),
    source_means_ptr(source_means),
    source_covs_ptr(source_covs) {}

  __device__ float operator()(const thrust::pair<int, int>& source_target_correspondence) const {
    const int source_idx = source_target_correspondence.first;
    const int target_idx = source_target_correspondence.second;
    if (source_idx < 0 || target_idx < 0) {
      return 0.0f;
    }

    const Eigen::Isometry3f& xl = *thrust::raw_pointer_cast(linearization_point_ptr);
    const Eigen::Matrix3f Rl = xl.linear();

    const Eigen::Isometry3f& xe = *thrust::raw_pointer_cast(evaluation_point_ptr);
    const Eigen::Matrix3f Re = xe.linear();
    const Eigen::Vector3f te = xe.translation();

    const Eigen::Vector3f& mean_A = thrust::raw_pointer_cast(source_means_ptr)[source_idx];
    const Eigen::Matrix3f& cov_A = thrust::raw_pointer_cast(source_covs_ptr)[source_idx];
    const Eigen::Vector3f transed_mean_A = Re * mean_A + te;

    const Eigen::Vector3f& mean_B = thrust::raw_pointer_cast(voxel_means_ptr)[target_idx];
    const Eigen::Matrix3f& cov_B = thrust::raw_pointer_cast(voxel_covs_ptr)[target_idx];

    const int num_points = thrust::raw_pointer_cast(voxel_num_points_ptr)[target_idx];

    const Eigen::Matrix3f RCR = (Rl * cov_A * Rl.transpose());
    const Eigen::Matrix3f RCR_inv = (cov_B + RCR).inverse();
    Eigen::Vector3f error = mean_B - transed_mean_A;

    return 0.5f * error.transpose() * RCR_inv * error;
  }

  thrust::device_ptr<const Eigen::Isometry3f> linearization_point_ptr;
  thrust::device_ptr<const Eigen::Isometry3f> evaluation_point_ptr;

  thrust::device_ptr<const int> voxel_num_points_ptr;
  thrust::device_ptr<const Eigen::Vector3f> voxel_means_ptr;
  thrust::device_ptr<const Eigen::Matrix3f> voxel_covs_ptr;

  thrust::device_ptr<const Eigen::Vector3f> source_means_ptr;
  thrust::device_ptr<const Eigen::Matrix3f> source_covs_ptr;
};

}  // namespace gtsam_ext
