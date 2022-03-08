

# P192 AWS 공급자 정의
provider "aws" {
  region = var.aws_region

}

# 클러스터 액세스 관리 (P192)
# 클러스터 수준에서 EKS가 node와 마이크로서비스를 실행할 수 있는 정책과 보안규칙을 정의
locals {
  cluster_name = "${var.cluster_name}-${var.env_name}"
}

resource "aws_iam_role" "ms-cluster" {
  name               = local.cluster_name
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principle": {
                "Service": "eks.amazonaws.com"
            },
            "Action": "stst:AssumeRole"
        }
    ]
}
POLICY 
}

# 관리형 IAM 정책을 IAM 역할에 연결

resource "aws_iam_role_policy_attachment" "ms-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "anr:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.ms-cluster.name
}

# 네트워드 보안 정책을 정의 (P193)
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "ms-cluster" {
  name        = local.cluster_name
  description = "Cluster communication with worker nodes"
  vpc_id      = var.vpc_id

  # 아웃바운드 규칙 (송신 규칙)
  # 모든 아웃바운드 트래픽을 허용 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ms-up-running"
  }

  #   # 인바운드 규칙 (수신 규칙)
  #   # 인바운드 규칙을 정의하지 않음 = 모든 인바운드 트래픽을 허용하지 않음
  #   ingress {
  #   }
}



# 클러스터에 대한 선언을 추가
resource "aws_eks_cluster" "ms-up-running" {
  name     = local.cluster_name
  role_arn = aws_iam_role.ms-cluster.arn
  vpc_config {
    security_group_ids = [aws_security_group.ms-cluster.id]
    subnet_ids         = var.cluster_subnet_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.ms-cluster-AmazonEKSClusterPolicy
  ]

}


# EKS 노드 그룹에 적용할 역할과 정책을 정의 (P195)
resource "aws_iam_role" "ms-node" {
  name               = "${local.cluster_name}.node"
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow", 
            "Principal": {
                "Service": "ec2.amazonaws.com"
            }, 
            "Action": "sts:AssumeRole"
        }
    ]
}
POLICY    
}


resource "aws_iam_role_policy_attachment" "ms-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.ms-node.name
}

resource "aws_iam_role_policy_attachment" "ms-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.ms-node.name
}

resource "aws_iam_role_policy_attachment" "ms-node-AmazonEC2ContainerRegistryPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPolicy"
  role       = aws_iam_role.ms-node.name
}

# EKS 노드 그룹을 정의
resource "aws_eks_node_group" "ms-node-group" {
  cluster_name    = aws_eks_cluster.ms-up-running.name
  node_group_name = "microservices"
  node_role_arn   = aws_iam_role.ms-node.arn
  subnet_ids      = var.nodegroup_subnet_ids

  scaling_config {
    desired_size = var.nodegroup_desired_size
    max_size     = var.nodegroup_max_size
    min_size     = var.nodegroup_min_size
  }

  disk_size      = var.nodegroup_disk_size
  instance_types = var.nodegroup_instance_types

  depends_on = [
    aws_iam_role_policy_attachment.ms-node-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.ms-node-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.ms-node-AmazonEC2ContainerRegistryPolicy
  ]

}

# kubeconfig 파일 생성 (P197)
# https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file
resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  content  = <<KUBECONFIG_END
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${aws_eks_cluster.ms-up-running.certificate_authority.0.data}
    server: ${aws_eks_cluster.ms-up-running.endpoint}
  name: ${aws_eks_cluster.ms-up-running.arn}
contexts:
- context:
    cluster: ${aws_eks_cluster.ms-up-running.arn}
    user: ${aws_eks_cluster.ms-up-running.arn}
  name: ${aws_eks_cluster.ms-up-running.arn}
current-context: ${aws_eks_cluster.ms-up-running.arn}
kind: Config
preferences: {}
users:
- name: ${aws_eks_cluster.ms-up-running.arn}
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
      - "token"
      - "-i"
      - "${aws_eks_cluster.ms-up-running.name}"
KUBECONFIG_END
}

