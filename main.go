// Copyright (c) 2021 Red Hat, Inc.
// Copyright Contributors to the Open Cluster Management project

package main

import (
	"flag"
	"fmt"
	"os"
	"runtime"
	"strings"

	// Import all Kubernetes client auth plugins (e.g. Azure, GCP, OIDC, etc.)
	// to ensure that exec-entrypoint and run can make use of them.
	v1 "k8s.io/api/core/v1"
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	policiesv1 "github.com/open-cluster-management/governance-policy-propagator/api/v1"
	"github.com/spf13/pflag"
	k8sruntime "k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	corev1 "k8s.io/client-go/kubernetes/typed/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/cache"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"

	"github.com/open-cluster-management/governance-policy-status-sync/controllers/sync"
	"github.com/open-cluster-management/governance-policy-status-sync/tool"
	"github.com/open-cluster-management/governance-policy-status-sync/version"
	//+kubebuilder:scaffold:imports
)

var (
	eventsScheme = k8sruntime.NewScheme()
	log          = logf.Log.WithName("setup")
	scheme       = k8sruntime.NewScheme()
)

func printVersion() {
	log.Info(fmt.Sprintf("Operator Version: %s", version.Version))
	log.Info(fmt.Sprintf("Go Version: %s", runtime.Version()))
	log.Info(fmt.Sprintf("Go OS/Arch: %s/%s", runtime.GOOS, runtime.GOARCH))
}

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))
	utilruntime.Must(v1.AddToScheme(eventsScheme))

	utilruntime.Must(policiesv1.AddToScheme(scheme))
	//+kubebuilder:scaffold:scheme
}

// GetWatchNamespace returns the Namespace the operator should be watching for changes
func GetWatchNamespace() (string, error) {
	// WatchNamespaceEnvVar is the constant for env variable WATCH_NAMESPACE
	// which specifies the Namespace to watch.
	// An empty value means the operator is running with cluster scope.
	var watchNamespaceEnvVar = "WATCH_NAMESPACE"

	ns, found := os.LookupEnv(watchNamespaceEnvVar)
	if !found {
		return "", fmt.Errorf("%s must be set", watchNamespaceEnvVar)
	}
	return ns, nil
}

func main() {
	// custom flags for the controler
	tool.ProcessFlags()

	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)

	pflag.Parse()

	logf.SetLogger(zap.New())

	printVersion()

	// Get hubconfig to talk to hub apiserver
	if tool.Options.HubConfigFilePathName == "" {
		found := false
		tool.Options.HubConfigFilePathName, found = os.LookupEnv("HUB_CONFIG")
		if found {
			log.Info("Found ENV HUB_CONFIG, initializing using", "tool.Options.HubConfigFilePathName",
				tool.Options.HubConfigFilePathName)
		}
	}

	hubCfg, err := clientcmd.BuildConfigFromFlags("", tool.Options.HubConfigFilePathName)

	if err != nil {
		log.Error(err, "")
		os.Exit(1)
	}

	// Get managedconfig to talk to managed apiserver
	var managedCfg *rest.Config
	if tool.Options.ManagedConfigFilePathName == "" {
		found := false
		tool.Options.ManagedConfigFilePathName, found = os.LookupEnv("MANAGED_CONFIG")
		if found {
			log.Info("Found ENV MANAGED_CONFIG, initializing using", "tool.Options.ManagedConfigFilePathName",
				tool.Options.ManagedConfigFilePathName)
			managedCfg, err = clientcmd.BuildConfigFromFlags("", tool.Options.ManagedConfigFilePathName)
			if err != nil {
				log.Error(err, "")
				os.Exit(1)
			}
		} else {
			managedCfg, err = config.GetConfig()
			if err != nil {
				log.Error(err, "")
				os.Exit(1)
			}
		}
	}

	hubClient, err := client.New(hubCfg, client.Options{Scheme: scheme})
	if err != nil {
		log.Error(err, "Failed to generate client to the hub cluster")
		os.Exit(1)
	}
	var kubeClient kubernetes.Interface = kubernetes.NewForConfigOrDie(hubCfg)

	eventBroadcaster := record.NewBroadcaster()
	namespace, err := GetWatchNamespace()
	if err != nil {
		log.Error(err, "Failed to get watch namespace")
		os.Exit(1)
	}
	eventBroadcaster.StartRecordingToSink(&corev1.EventSinkImpl{Interface: kubeClient.CoreV1().Events(namespace)})
	hubRecorder := eventBroadcaster.NewRecorder(eventsScheme, v1.EventSource{Component: sync.ControllerName})

	options := manager.Options{
		LeaderElection:     tool.Options.EnableLeaderElection,
		LeaderElectionID:   "policy-status-sync.open-cluster-management.io",
		MetricsBindAddress: "0",
		Namespace:          namespace,
		Port:               9443,
		Scheme:             scheme,
	}
	// Add support for MultiNamespace set in WATCH_NAMESPACE (e.g ns1,ns2)
	// Note that this is not intended to be used for excluding namespaces, this is better done via a Predicate
	// Also note that you may face performance issues when using this with a high number of namespaces.
	// More Info: https://godoc.org/github.com/kubernetes-sigs/controller-runtime/pkg/cache#MultiNamespacedCacheBuilder
	if strings.Contains(namespace, ",") {
		options.Namespace = ""
		options.NewCache = cache.MultiNamespacedCacheBuilder(strings.Split(namespace, ","))
	}

	mgr, err := ctrl.NewManager(managedCfg, options)
	if err != nil {
		log.Error(err, "unable to start manager")
		os.Exit(1)
	}

	if err = (&sync.PolicyReconciler{
		HubClient:       hubClient,
		HubRecorder:     hubRecorder,
		ManagedClient:   mgr.GetClient(),
		ManagedRecorder: mgr.GetEventRecorderFor(sync.ControllerName),
		Scheme:          mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		log.Error(err, "unable to create controller", "controller", "Policy")
		os.Exit(1)
	}
	//+kubebuilder:scaffold:builder

	// create namespace with labels
	var generatedClient kubernetes.Interface = kubernetes.NewForConfigOrDie(managedCfg)
	if err := tool.CreateClusterNs(&generatedClient, namespace); err != nil {
		log.Error(err, "")
		os.Exit(1)
	}

	log.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		log.Error(err, "problem running manager")
		os.Exit(1)
	}
}
