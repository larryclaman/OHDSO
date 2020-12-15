using Microsoft.AspNetCore.Identity;
using System.Threading.Tasks;

namespace Microsoft.eShopWeb.Infrastructure.Identity
{
    public class AppIdentityDbContextSeed
    {
        public static async Task SeedAsync(UserManager<ApplicationUser> userManager)
        {
            var defaultUser = new ApplicationUser { UserName = "demouser@microsoft.com", Email = "demouser@microsoft.com" };
            
            //[SuppressMessage("Microsoft.Security", "CS002:SecretInNextLine", Justification="OHtest")]
            await userManager.CreateAsync(defaultUser, "Pass@word1");
        }
    }
}
