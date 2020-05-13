// Copyright (c) 2020 Red Hat, Inc.

package e2e

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	policiesv1 "github.com/open-cluster-management/governance-policy-propagator/pkg/apis/policies/v1"
	"github.com/open-cluster-management/governance-policy-propagator/test/utils"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const case1PolicyName string = "default.case1-test-policy"
const case1PolicyYaml string = "../resources/case1_mutation_recovery/case1-test-policy.yaml"

var _ = Describe("Test mutation recovery", func() {
	BeforeEach(func() {
		By("Creating a policy on hub cluster in ns:" + testNamespace)
		utils.Kubectl("apply", "-f", case1PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_hub")
		hubPlc := utils.GetWithTimeout(clientHubDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(hubPlc).NotTo(BeNil())
		By("Creating a policy on managed cluster in ns:" + testNamespace)
		utils.Kubectl("apply", "-f", case1PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_managed")
		managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(managedPlc).NotTo(BeNil())
	})
	AfterEach(func() {
		By("Deleting a policy on hub cluster in ns:" + testNamespace)
		utils.Kubectl("delete", "-f", case1PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_hub")
		utils.Kubectl("delete", "-f", case1PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_managed")
		opt := metav1.ListOptions{}
		utils.ListWithTimeout(clientHubDynamic, gvrPolicy, opt, 0, true, defaultTimeoutSeconds)
		utils.ListWithTimeout(clientManagedDynamic, gvrPolicy, opt, 0, true, defaultTimeoutSeconds)
	})
	It("Should recover policy on managed if spec.remediationAction being modified", func() {
		By("Patching " + case1PolicyYaml + " on managed with spec.remediationAction = enforce")
		managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Expect(managedPlc.Object["spec"].(map[string]interface{})["remediationAction"]).To(Equal("inform"))
		managedPlc.Object["spec"].(map[string]interface{})["remediationAction"] = "enforce"
		managedPlc, err := clientManagedDynamic.Resource(gvrPolicy).Namespace(testNamespace).Update(managedPlc, metav1.UpdateOptions{})
		Expect(err).To(BeNil())
		By("Comparing spec between hub and managed policy")
		hubPlc := utils.GetWithTimeout(clientHubDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Eventually(func() interface{} {
			managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
			return managedPlc.Object["spec"]
		}, defaultTimeoutSeconds, 1).Should(utils.SemanticEqual(hubPlc.Object["spec"]))
	})
	It("Should recover policy on managed if spec.policyTemplates being modified", func() {
		By("Patching " + case1PolicyYaml + " on managed with spec.policyTemplate = {}")
		managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		managedPlc.Object["spec"].(map[string]interface{})["policy-templates"] = []*policiesv1.PolicyTemplate{}
		managedPlc, err := clientManagedDynamic.Resource(gvrPolicy).Namespace(testNamespace).Update(managedPlc, metav1.UpdateOptions{})
		Expect(err).To(BeNil())
		By("Comparing spec between hub and managed policy")
		hubPlc := utils.GetWithTimeout(clientHubDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Eventually(func() interface{} {
			managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
			return managedPlc.Object["spec"]
		}, defaultTimeoutSeconds, 1).Should(utils.SemanticEqual(hubPlc.Object["spec"]))
	})
	It("Should recover policy on managed if being deleted", func() {
		By("Deleting " + case1PolicyYaml + " on managed with spec.policyTemplate = {}")
		utils.Kubectl("delete", "-f", case1PolicyYaml, "-n", testNamespace,
			"--kubeconfig=../../kubeconfig_managed")
		By("Comparing spec between hub and managed policy")
		hubPlc := utils.GetWithTimeout(clientHubDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
		Eventually(func() interface{} {
			managedPlc := utils.GetWithTimeout(clientManagedDynamic, gvrPolicy, case1PolicyName, testNamespace, true, defaultTimeoutSeconds)
			return managedPlc.Object["spec"]
		}, defaultTimeoutSeconds, 1).Should(utils.SemanticEqual(hubPlc.Object["spec"]))
	})
})