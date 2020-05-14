// Copyright (c) 2020 Red Hat, Inc.

package e2e

import (
	"fmt"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/open-cluster-management/governance-policy-propagator/test/utils"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const case2PolicyName string = "default.case2-test-policy"
const case2PolicyYaml string = "../resources/case2_status_sync/case2-test-policy.yaml"

// const testNamespace string = "managed"

var _ = Describe("Test status sync", func() {
	BeforeEach(func() {
		By("Creating a policy on hub cluster in ns:" + testNamespace)
		utils.Kubectl("apply", "-f", case2PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_hub")
		hubPlc := utils.GetWithTimeout(clientHubDynamic, gvrPolicy, case2PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(hubPlc).NotTo(BeNil())
		By("Creating a policy on managed cluster in ns:" + testNamespace)
		utils.Kubectl("apply", "-f", case2PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_managed")
		managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case2PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(managedPlc).NotTo(BeNil())
	})
	AfterEach(func() {
		By("Deleting a policy on hub cluster in ns:" + testNamespace)
		utils.Kubectl("delete", "-f", case2PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_hub")
		utils.Kubectl("delete", "-f", case2PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_managed")
		opt := metav1.ListOptions{}
		utils.ListWithTimeout(clientHubDynamic, gvrPolicy, opt, 0, true, defaultTimeoutSeconds)
		utils.ListWithTimeout(clientManagedDynamic, gvrPolicy, opt, 0, true, defaultTimeoutSeconds)
	})
	It("Should set status to compliant", func() {
		By("Generating an compliant event on the policy")
		managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case2PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(managedPlc).NotTo(BeNil())
		managedRecorder.Event(managedPlc, "Normal", "policy: managed/case2-test-policy-trustedcontainerpolicy", fmt.Sprintf("Compliant; No violation detected"))
		// yamlStatus := utils.ParseYaml("../resources/case2_status_sync/status-compliant.yaml")
		Eventually(func() interface{} {
			managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case2PolicyName, testNamespace, true, defaultTimeoutSeconds)
			return managedPlc.Object["status"].(map[string]interface{})["compliant"]
		}, defaultTimeoutSeconds, 1).Should(Equal("Compliant"))
	})
	It("Should set status to NonCompliant", func() {
		By("Generating an compliant event on the policy")
		managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case2PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(managedPlc).NotTo(BeNil())
		managedRecorder.Event(managedPlc, "Normal", "policy: managed/case2-test-policy-trustedcontainerpolicy", fmt.Sprintf("NonCompliant; there is violation"))
		Eventually(func() interface{} {
			managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case2PolicyName, testNamespace, true, defaultTimeoutSeconds)
			return managedPlc.Object["status"].(map[string]interface{})["compliant"]
		}, defaultTimeoutSeconds, 1).Should(Equal("NonCompliant"))
	})
})
