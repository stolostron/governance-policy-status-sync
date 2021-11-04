module github.com/open-cluster-management/governance-policy-status-sync

go 1.16

require (
	github.com/onsi/ginkgo v1.14.1
	github.com/onsi/gomega v1.10.1
	github.com/open-cluster-management/addon-framework v0.0.0-20210415135036-d591b71789d6
	github.com/open-cluster-management/governance-policy-propagator v0.0.0-20210330231547-932d5d73e0c3
	github.com/operator-framework/operator-sdk v0.19.4
	github.com/spf13/pflag v1.0.5
	k8s.io/api v0.20.5
	k8s.io/apimachinery v0.20.5
	k8s.io/apiserver v0.20.5
	k8s.io/client-go v12.0.0+incompatible
	k8s.io/klog v1.0.0
	sigs.k8s.io/controller-runtime v0.6.2
)

replace (
	github.com/go-logr/zapr => github.com/go-logr/zapr v0.4.0
	k8s.io/client-go => k8s.io/client-go v0.20.5
)
