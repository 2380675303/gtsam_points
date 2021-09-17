#include <gtsam_ext/factors/integrated_vgicp_factor_gpu.hpp>

#include <gtsam/geometry/Pose3.h>
#include <gtsam/linear/HessianFactor.h>

#include <gtsam_ext/cuda/kernels/linearized_system.cuh>
#include <gtsam_ext/cuda/stream_temp_buffer_roundrobin.hpp>
#include <gtsam_ext/factors/integrated_vgicp_derivatives.cuh>

namespace gtsam_ext {

IntegratedVGICPFactorGPU::IntegratedVGICPFactorGPU(gtsam::Key target_key, gtsam::Key source_key, const VoxelizedFrame::ConstPtr& target, const Frame::ConstPtr& source)
: IntegratedVGICPFactorGPU(target_key, source_key, target, source, nullptr, nullptr) {}

IntegratedVGICPFactorGPU::IntegratedVGICPFactorGPU(
  gtsam::Key target_key,
  gtsam::Key source_key,
  const VoxelizedFrame::ConstPtr& target,
  const Frame::ConstPtr& source,
  CUstream_st* stream,
  std::shared_ptr<TempBufferManager> temp_buffer)
: gtsam_ext::NonlinearFactorGPU(gtsam::cref_list_of<2>(target_key)(source_key)),
  is_binary(true),
  fixed_target_pose(Eigen::Isometry3f::Identity()),
  target(target),
  source(source),
  derivatives(new IntegratedVGICPDerivatives(target, source, stream, temp_buffer)),
  linearized(false),
  linearization_point(Eigen::Isometry3f::Identity()) {}

IntegratedVGICPFactorGPU::~IntegratedVGICPFactorGPU() {}

size_t IntegratedVGICPFactorGPU::linearization_input_size() const {
  return sizeof(Eigen::Isometry3f);
}

size_t IntegratedVGICPFactorGPU::linearization_output_size() const {
  return sizeof(LinearizedSystem6);
}

size_t IntegratedVGICPFactorGPU::evaluation_input_size() const {
  return sizeof(Eigen::Isometry3f);
}

size_t IntegratedVGICPFactorGPU::evaluation_output_size() const {
  return sizeof(float);
}

Eigen::Isometry3f IntegratedVGICPFactorGPU::calc_delta(const gtsam::Values& values) const {
  if (!is_binary) {
    gtsam::Pose3 source_pose = values.at<gtsam::Pose3>(keys_[0]);
    gtsam::Pose3 delta = gtsam::Pose3(fixed_target_pose.inverse().cast<double>().matrix()) * source_pose;
    return Eigen::Isometry3f(delta.matrix().cast<float>());
  }

  gtsam::Pose3 target_pose = values.at<gtsam::Pose3>(keys_[0]);
  gtsam::Pose3 source_pose = values.at<gtsam::Pose3>(keys_[1]);
  gtsam::Pose3 delta = target_pose.inverse() * source_pose;

  return Eigen::Isometry3f(delta.matrix().cast<float>());
}

double IntegratedVGICPFactorGPU::error(const gtsam::Values& values) const {
  double err;
  if (evaluation_result) {
    err = evaluation_result.get();
    evaluation_result = boost::none;
  } else {
    std::cerr << "warning: computing error in sync mode seriously affects the processing speed!!" << std::endl;

    if (!linearized) {
      linearize(values);
    }

    Eigen::Isometry3f evaluation_point = calc_delta(values);
    err = derivatives->compute_error(linearization_point, evaluation_point);
  }

  return err;
}

boost::shared_ptr<gtsam::GaussianFactor> IntegratedVGICPFactorGPU::linearize(const gtsam::Values& values) const {
  linearized = true;
  linearization_point = calc_delta(values);

  LinearizedSystem6 l;

  if (linearization_result) {
    l = *linearization_result;
    linearization_result.reset();
  } else {
    l = derivatives->linearize(linearization_point);
  }

  gtsam::HessianFactor::shared_ptr factor;

  if (is_binary) {
    factor.reset(new gtsam::HessianFactor(
      keys_[0],
      keys_[1],
      l.H_target.cast<double>(),
      l.H_target_source.cast<double>(),
      -l.b_target.cast<double>(),
      l.H_source.cast<double>(),
      -l.b_source.cast<double>(),
      0.0));
  } else {
    factor.reset(new gtsam::HessianFactor(keys_[0], l.H_source.cast<double>(), -l.b_source.cast<double>(), 0.0));
  }

  return factor;
}

void IntegratedVGICPFactorGPU::set_linearization_point(const gtsam::Values& values, void* lin_input_cpu) {
  Eigen::Isometry3f* linearization_point = reinterpret_cast<Eigen::Isometry3f*>(lin_input_cpu);
  *linearization_point = calc_delta(values);
}

void IntegratedVGICPFactorGPU::set_evaluation_point(const gtsam::Values& values, void* eval_input_cpu) {
  Eigen::Isometry3f* evaluation_point = reinterpret_cast<Eigen::Isometry3f*>(eval_input_cpu);
  *evaluation_point = calc_delta(values);
}

void IntegratedVGICPFactorGPU::issue_linearize(const void* lin_input_cpu, const thrust::device_ptr<const void>& lin_input_gpu, const thrust::device_ptr<void>& lin_output_gpu) {
  auto linearization_point = reinterpret_cast<const Eigen::Isometry3f*>(lin_input_cpu);
  auto linearization_point_gpu = thrust::reinterpret_pointer_cast<thrust::device_ptr<const Eigen::Isometry3f>>(lin_input_gpu);
  auto linearized_gpu = thrust::reinterpret_pointer_cast<thrust::device_ptr<LinearizedSystem6>>(lin_output_gpu);

  derivatives->update_inliers(*linearization_point, linearization_point_gpu);
  derivatives->issue_linearize(linearization_point_gpu, linearized_gpu);
}

void IntegratedVGICPFactorGPU::store_linearized(const void* lin_output_cpu) {
  auto linearized = reinterpret_cast<const LinearizedSystem6*>(lin_output_cpu);
  linearization_result.reset(new LinearizedSystem6(*linearized));
  evaluation_result = linearized->error;
}

void IntegratedVGICPFactorGPU::issue_compute_error(
  const void* lin_input_cpu,
  const void* eval_input_cpu,
  const thrust::device_ptr<const void>& lin_input_gpu,
  const thrust::device_ptr<const void>& eval_input_gpu,
  const thrust::device_ptr<void>& eval_output_gpu) {
  //
  auto linearization_point = reinterpret_cast<const Eigen::Isometry3f*>(lin_input_cpu);
  auto evaluation_point = reinterpret_cast<const Eigen::Isometry3f*>(eval_input_cpu);

  auto linearization_point_gpu = thrust::reinterpret_pointer_cast<thrust::device_ptr<const Eigen::Isometry3f>>(lin_input_gpu);
  auto evaluation_point_gpu = thrust::reinterpret_pointer_cast<thrust::device_ptr<const Eigen::Isometry3f>>(eval_input_gpu);

  auto error_gpu = thrust::reinterpret_pointer_cast<thrust::device_ptr<float>>(eval_output_gpu);

  Eigen::Isometry3f l, e;
  cudaMemcpy(l.data(), thrust::raw_pointer_cast(linearization_point_gpu), sizeof(Eigen::Isometry3f), cudaMemcpyDeviceToHost);
  cudaMemcpy(e.data(), thrust::raw_pointer_cast(evaluation_point_gpu), sizeof(Eigen::Isometry3f), cudaMemcpyDeviceToHost);

  derivatives->issue_compute_error(linearization_point_gpu, evaluation_point_gpu, error_gpu);
}

void IntegratedVGICPFactorGPU::store_computed_error(const void* eval_output_cpu) {
  auto evaluated = reinterpret_cast<const float*>(eval_output_cpu);
  evaluation_result = *evaluated;
}

void IntegratedVGICPFactorGPU::sync() {
  derivatives->sync_stream();
}
}  // namespace gtsam_ext