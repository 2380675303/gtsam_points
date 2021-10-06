#pragma once

#include <Eigen/Core>

namespace gtsam_ext {

struct BALMFeature {
public:
  EIGEN_MAKE_ALIGNED_OPERATOR_NEW

  BALMFeature(const std::vector<Eigen::Vector3d, Eigen::aligned_allocator<Eigen::Vector3d>>& points) {
    Eigen::Vector3d sum_pts = Eigen::Vector3d::Zero();
    Eigen::Matrix3d sum_cross = Eigen::Matrix3d::Zero();
    for (const auto& pt : points) {
      sum_pts += pt;
      sum_cross += pt * pt.transpose();
    }

    num_points = points.size();
    mean = sum_pts / points.size();
    cov = (sum_cross - mean * sum_pts.transpose()) / points.size();

    Eigen::SelfAdjointEigenSolver<Eigen::Matrix3d> eig(cov);
    eigenvalues = eig.eigenvalues();
    eigenvectors = eig.eigenvectors();
  }

  template <int k>
  Eigen::Matrix<double, 1, 3> Ji(const Eigen::Vector3d& p_i) const {
    Eigen::Vector3d u = eigenvectors.col(k);
    return 2.0 / num_points * (p_i - mean).transpose() * u * u.transpose();
  }

  template <int k>
  Eigen::Matrix3d Hij(const Eigen::Vector3d& p_i, const Eigen::Vector3d& p_j, bool i_equals_j) const {
    const int N = num_points;
    Eigen::Matrix3d F_k;
    F_k.row(0) = Fmn<0, k>(p_j);
    F_k.row(1) = Fmn<1, k>(p_j);
    F_k.row(2) = Fmn<2, k>(p_j);

    const auto& u_k = eigenvectors.col(k);
    const auto& U = eigenvectors;

    if (i_equals_j) {
      const auto t1 = (N - 1) / static_cast<double>(N) * u_k * u_k.transpose();
      const auto t2 = u_k * (p_i - mean).transpose() * U * F_k;
      const auto t3 = U * F_k * (u_k.transpose() * (p_i - mean));
      Eigen::Matrix3d H = 2.0 / N * (t1 + t2 + t3);
      return H;
    } else {
      const auto t1 = -1.0 / N * u_k * u_k.transpose();
      const auto t2 = u_k * (p_i - mean).transpose() * U * F_k;
      const auto t3 = U * F_k * (u_k.transpose() * (p_i - mean));
      Eigen::Matrix3d H = 2.0 / N * (t1 + t2 + t3);

      return H;
    }
  }

  template <int m, int n>
  Eigen::Matrix<double, 1, 3> Fmn(const Eigen::Vector3d& pt) const {
    if constexpr (m == n) {
      return Eigen::Matrix<double, 1, 3>::Zero();
    } else {
      const double l_m = eigenvalues[m];
      const double l_n = eigenvalues[n];
      const auto& u_m = eigenvectors.col(m);
      const auto& u_n = eigenvectors.col(n);

      const auto lhs = (pt - mean).transpose() / (num_points * (l_n - l_m));
      const auto rhs = u_m * u_n.transpose() + u_n * u_m.transpose();
      return lhs * rhs;
    }
  }

  int num_points;
  Eigen::Vector3d mean;
  Eigen::Matrix3d cov;

  Eigen::Vector3d eigenvalues;
  Eigen::Matrix3d eigenvectors;
};

}